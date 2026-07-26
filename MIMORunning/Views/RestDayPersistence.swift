import SwiftUI
import SwiftData
import Photos
import UIKit

// MARK: - RestDayOneLinerSheet + Persistence

extension RestDayOneLinerSheet {

    func loadEntry() {
        storyModeRecipes    = []
        videoModeRecipes    = []
        slideModeRecipes    = []
        clipRecipes         = []
        videoTitle          = ""
        titleStyle          = OneLinerTitleStyle()
        videoModeTitle      = ""
        videoModeTitleStyle = OneLinerTitleStyle()
        slideModeTitle      = ""
        slideModeTitleStyle = OneLinerTitleStyle()
        selectedTemplate    = .story
        currentClipIndex    = 0

        if let entry = gradientEntry {
            text       = entry.text
            fontChoice = entry.font
            textColor     = entry.textColor
            position      = entry.position
            if videoTextEntry != nil {
                modelContext.delete(entry)
                try? modelContext.save()
            }
        }

        guard let vEntry = videoTextEntry else { return }
        fontChoice = vEntry.font
        textColor  = vEntry.textColor
        position   = vEntry.position
        let raw = vEntry.text

        if raw.hasPrefix("v4recipes\n") {
            let jsonStr = String(raw.dropFirst("v4recipes\n".count))
            guard let data  = jsonStr.data(using: .utf8),
                  let store = try? JSONDecoder().decode(PerModeRecipeStore.self, from: data) else { return }
            storyModeRecipes = restoreRecipes(from: store.story)
            videoModeRecipes = restoreRecipes(from: store.video)
            slideModeRecipes = restoreRecipes(from: store.slide)
            if let videoSet = store.video {
                videoModeTitle      = videoSet.videoTitle
                videoModeTitleStyle = restoreTitleStyle(from: videoSet)
            }
            if let slideSet = store.slide {
                slideModeTitle      = slideSet.videoTitle
                slideModeTitleStyle = restoreTitleStyle(from: slideSet)
            }
            if let mode = RestDayTemplate(rawValue: store.activeMode) { selectedTemplate = mode }
            loadFromBackingStore(for: selectedTemplate)
            switch selectedTemplate {
            case .video: muteVideoAudio = store.video?.muteAudio ?? false
            case .slide: muteVideoAudio = store.slide?.muteAudio ?? false
            case .story: break
            }
            // 오염 데이터 자동 정리: 로드 직후 sanitized 상태를 DB에 재기록
            Task { @MainActor in saveEntry() }
        } else if raw.hasPrefix("v3recipes\n") {
            let jsonStr = String(raw.dropFirst("v3recipes\n".count))
            guard let data  = jsonStr.data(using: .utf8),
                  let saved = try? JSONDecoder().decode(SavedRecipeSet.self, from: data),
                  !saved.clips.isEmpty else { return }
            muteVideoAudio = saved.muteAudio
            let restored = restoreRecipes(from: saved)
            let mode = saved.mode == "story" ? RestDayTemplate.story
                                             : (saved.isPhotoSlide ? .slide : .video)
            switch mode {
            case .story: storyModeRecipes = restored
            case .video: videoModeRecipes = restored
            case .slide: slideModeRecipes = restored
            }
            selectedTemplate = mode
            clipRecipes = restored
            currentClipIndex = 0
            Task { @MainActor in saveEntry() }
        } else if raw.hasPrefix("v2clips\n") {
            let section = String(raw.dropFirst("v2clips\n".count))
            savedClipLines = section
                .components(separatedBy: "\n---CLIP---\n")
                .map { $0.components(separatedBy: "\n") }
        } else {
            let linesArr = raw.components(separatedBy: "\n")
            if let first = linesArr.first, let count = Int(first), count > 0 {
                let texts = (0..<count).map { i in (i + 1) < linesArr.count ? linesArr[i + 1] : "" }
                savedClipLines = [texts]
            }
        }
    }

    func applyStyle(to entry: OneLinerEntry) {
        entry.text      = text
        entry.font      = fontChoice
        entry.textColor = textColor
        entry.position  = position
        entry.showDate  = true
    }

    func saveEntry() {
        syncActiveToBackingStore()

        let storySet = buildRecipeSet(from: storyModeRecipes, mode: "story")
        let videoSet = buildRecipeSet(from: videoModeRecipes, mode: nil,
                                      title: videoModeTitle, titleStyleParam: videoModeTitleStyle)
        let slideSet = buildRecipeSet(from: slideModeRecipes, mode: nil, isPhotoSlide: true,
                                      title: slideModeTitle, titleStyleParam: slideModeTitleStyle)

        if storySet != nil || videoSet != nil || slideSet != nil {
            let store = PerModeRecipeStore(
                story: storySet, video: videoSet, slide: slideSet,
                activeMode: selectedTemplate.rawValue)
            if let data = try? JSONEncoder().encode(store),
               let json = String(data: data, encoding: .utf8) {
                let payload = "v4recipes\n" + json
                if let existing = videoTextEntry {
                    existing.text = payload; existing.font = fontChoice
                    existing.textColor = textColor; existing.position = position
                    existing.showDate = true
                } else {
                    let entry = OneLinerEntry(workoutID: workoutID, mediaRef: "videotexts")
                    entry.text = payload; entry.font = fontChoice
                    entry.textColor = textColor; entry.position = position
                    entry.showDate = true
                    modelContext.insert(entry)
                }
            }
            try? modelContext.save()
            return
        }

        // No clips — videoTextEntry(v4recipes) 도 정리
        if let vEntry = videoTextEntry { modelContext.delete(vEntry) }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = gradientEntry {
            if trimmed.isEmpty { modelContext.delete(existing) } else { applyStyle(to: existing) }
        } else if !trimmed.isEmpty {
            let entry = OneLinerEntry(workoutID: workoutID, mediaRef: nil)
            applyStyle(to: entry); modelContext.insert(entry)
        }
        try? modelContext.save()
    }

    func clearClipState() {
        for recipe in storyModeRecipes + videoModeRecipes + slideModeRecipes {
            if let ref = recipe.thumbRef       { ClipThumbStore.delete(ref: ref) }
            if let ref = recipe.storedPhotoRef { OneLinerPhotoStore.delete(mediaRef: ref) }
            if let ref = recipe.clipVideoRef   { ClipVideoStore.delete(ref: ref) }
        }
        storyModeRecipes = []
        videoModeRecipes = []
        slideModeRecipes = []
        clipRecipes      = []
        muteVideoAudio   = false
        selectedTemplate = .story
        if let vEntry = videoTextEntry { modelContext.delete(vEntry); try? modelContext.save() }
    }

    func markAsShared() {
        guard let vEntry = videoTextEntry else { return }
        if vEntry.text.hasPrefix("v4recipes\n") {
            let jsonStr = String(vEntry.text.dropFirst("v4recipes\n".count))
            guard let data  = jsonStr.data(using: .utf8),
                  var store = try? JSONDecoder().decode(PerModeRecipeStore.self, from: data) else { return }
            switch selectedTemplate {
            case .story: store.story?.isShared = true
            case .video: store.video?.isShared = true
            case .slide: store.slide?.isShared = true
            }
            if let newData = try? JSONEncoder().encode(store),
               let json    = String(data: newData, encoding: .utf8) {
                vEntry.text = "v4recipes\n" + json; try? modelContext.save()
            }
        } else if vEntry.text.hasPrefix("v3recipes\n") {
            let jsonStr = String(vEntry.text.dropFirst("v3recipes\n".count))
            guard let data  = jsonStr.data(using: .utf8),
                  var saved = try? JSONDecoder().decode(SavedRecipeSet.self, from: data) else { return }
            saved.isShared = true
            if let newData = try? JSONEncoder().encode(saved),
               let json    = String(data: newData, encoding: .utf8) {
                vEntry.text = "v3recipes\n" + json; try? modelContext.save()
            }
        }
    }

    func syncActiveToBackingStore() {
        // 소스없음 클립(assetID·clipVideoRef·storedPhotoRef 모두 nil)은 배열에 영구 저장 금지
        let valid = clipRecipes.filter {
            $0.assetIdentifier != nil || $0.clipVideoRef != nil || $0.storedPhotoRef != nil
        }
        switch selectedTemplate {
        case .story:
            storyModeRecipes = valid
        case .video:
            videoModeRecipes = valid
            videoModeTitle = videoTitle
            videoModeTitleStyle = titleStyle
        case .slide:
            slideModeRecipes = valid
            slideModeTitle = videoTitle
            slideModeTitleStyle = titleStyle
        }
    }

    func loadFromBackingStore(for template: RestDayTemplate) {
        switch template {
        case .story:
            clipRecipes = storyModeRecipes
            videoTitle  = ""
            titleStyle  = OneLinerTitleStyle()
        case .video:
            clipRecipes = videoModeRecipes
            videoTitle  = ""
            titleStyle  = OneLinerTitleStyle()
        case .slide:
            clipRecipes = slideModeRecipes
            videoTitle  = ""
            titleStyle  = OneLinerTitleStyle()
        }
        currentClipIndex = 0
    }

    func buildRecipeSet(from recipes: [ClipRecipe], mode: String?,
                        isPhotoSlide: Bool = false,
                        title: String = "",
                        titleStyleParam: OneLinerTitleStyle = OneLinerTitleStyle()) -> SavedRecipeSet? {
        guard !recipes.isEmpty else { return nil }
        let validRecipes = recipes.filter {
            $0.assetIdentifier != nil || $0.clipVideoRef != nil || $0.storedPhotoRef != nil
        }
        guard !validRecipes.isEmpty else { return nil }
        let descs = validRecipes.map { r in
            SavedClipDescriptor(
                assetID: r.assetIdentifier, clipVideoRef: r.clipVideoRef,
                photoRef: r.storedPhotoRef,
                thumbRef: r.thumbRef, trimStart: r.trimStart,
                trimEnd: r.trimEnd, fullDuration: r.fullDuration,
                lines: r.lines,
                fontID: r.fontChoice.rawValue,
                colorID: r.textColor.rawValue,
                anchorIdx: CardPosition.allCases.firstIndex(of: r.position),
                sizeID: r.sizeLevel.rawValue,
                effectID: "\(r.appearanceMode.rawValue)|\(r.decorEffect.rawValue)|B\(r.hasBorder ? 1 : 0)|\(r.flyDirection.rawValue)",
                speed: r.speed, cropOffsetX: Double(r.cropOffsetX),
                metricPace: r.metricPace, metricDistance: r.metricDistance, metricTime: r.metricTime,
                pdtAnchorIdx: CardPosition.allCases.firstIndex(of: r.pdtPosition),
                showRoute: r.showRoute,
                routeAnchorIdx: CardPosition.allCases.firstIndex(of: r.routePosition),
                showHRChart: r.showHRChart,
                chartTypeID:  r.chartOverlayType == .none ? nil : r.chartOverlayType.rawValue,
                pdtSizeID2:   r.pdtSizeLevel.rawValue,
                dataEffectID: r.dataAppearanceMode.rawValue)
        }
        return SavedRecipeSet(
            isPhotoSlide: isPhotoSlide || (mode == "story"),
            muteAudio: mode == "story" ? false : muteVideoAudio,
            clips: descs, isShared: false, mode: mode,
            videoTitle: title,
            titleAnchorIdx: CardPosition.allCases.firstIndex(of: titleStyleParam.position),
            titleFontID: titleStyleParam.fontChoice.rawValue,
            titleColorID: titleStyleParam.textColor.rawValue,
            titleSizeID: titleStyleParam.sizeLevel.rawValue,
            titleOutline: titleStyleParam.outline)
    }

    func restoreTitleStyle(from set: SavedRecipeSet) -> OneLinerTitleStyle {
        var style = OneLinerTitleStyle()
        if let idx = set.titleAnchorIdx, CardPosition.allCases.indices.contains(idx) {
            style.position = CardPosition.allCases[idx]
        }
        if let fid = set.titleFontID   { style.fontChoice = OneLinerFont.migrate(fid) }
        if let cid = set.titleColorID  { style.textColor  = OneLinerTextColor(rawValue: cid) ?? .white }
        if let sid = set.titleSizeID   { style.sizeLevel  = TextSizeLevel(rawValue: sid) ?? .medium }
        style.outline = set.titleOutline
        return style
    }

    func restoreRecipes(from saved: SavedRecipeSet?) -> [ClipRecipe] {
        guard let saved, !saved.clips.isEmpty else { return [] }
        var restored: [ClipRecipe] = []
        for desc in saved.clips {
            let thumb: UIImage?
            if let pr = desc.photoRef { thumb = OneLinerPhotoStore.load(mediaRef: pr) }
            else if let tr = desc.thumbRef { thumb = ClipThumbStore.load(ref: tr) }
            else { thumb = nil }
            let recipeURL: URL
            if let ref = desc.clipVideoRef, let stableURL = ClipVideoStore.fileURL(ref: ref),
               FileManager.default.fileExists(atPath: stableURL.path) {
                recipeURL = stableURL
            } else if desc.assetID != nil {
                recipeURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("mimo_placeholder_\(UUID().uuidString)")
            } else {
                recipeURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("mimo_placeholder_\(UUID().uuidString)")
            }
            var recipe = ClipRecipe(url: recipeURL, fullDuration: desc.fullDuration,
                                    thumbnail: thumb)
            recipe.trimStart       = desc.trimStart
            recipe.trimEnd         = desc.trimEnd
            // Sanitize: old code versions sometimes stored format prefix strings or raw JSON
            recipe.lines = desc.lines.map { line in
                let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.hasPrefix("v3slide") || t.hasPrefix("v3recipes")
                    || t.hasPrefix("v4recipes") || t.hasPrefix("v2clips")
                    || (t.count > 30 && t.hasPrefix("{") && t.hasSuffix("}")) {
                    return ""
                }
                return line
            }
            recipe.assetIdentifier = desc.assetID
            recipe.clipVideoRef    = desc.clipVideoRef
            recipe.storedPhotoRef  = desc.photoRef
            recipe.thumbRef        = desc.thumbRef
            recipe.fontChoice = OneLinerFont.migrate(desc.fontID)
            recipe.textColor  = desc.colorID.flatMap { OneLinerTextColor(rawValue: $0) } ?? textColor
            if let idx = desc.anchorIdx, CardPosition.allCases.indices.contains(idx) {
                recipe.position = CardPosition.allCases[idx]
            } else {
                recipe.position = position
            }
            recipe.sizeLevel = desc.sizeID.flatMap { TextSizeLevel(rawValue: $0) } ?? .medium
            if let eid = desc.effectID, eid.contains("|") {
                let parts = eid.split(separator: "|", maxSplits: 3).map(String.init)
                recipe.appearanceMode = parts.count > 0 ? (AppearanceMode(rawValue: parts[0]) ?? .typing) : .typing
                recipe.decorEffect    = parts.count > 1 ? (DecorEffect(rawValue: parts[1]) ?? .none) : .none
                if parts.count > 2 {
                    let r = parts[2]
                    if r.hasPrefix("B") {
                        recipe.hasBorder = r.contains("B1")
                    } else {
                        switch r {
                        case "1", "outline": recipe.hasBorder = true
                        default:             recipe.hasBorder = false
                        }
                    }
                }
                recipe.flyDirection = parts.count > 3 ? (FlyInDirection(rawValue: parts[3]) ?? .trailing) : .trailing
            } else {
                recipe.appearanceMode = .typing
                recipe.decorEffect    = .none
                recipe.hasBorder      = false
            }
            recipe.speed       = desc.speed
            recipe.cropOffsetX = CGFloat(desc.cropOffsetX)
            recipe.metricPace     = desc.metricPace
            recipe.metricDistance = desc.metricDistance
            recipe.metricTime     = desc.metricTime
            if let a = desc.pdtAnchorIdx, CardPosition.allCases.indices.contains(a) {
                recipe.pdtPosition = CardPosition.allCases[a]
            }
            if let ct = desc.chartTypeID, let type = ChartOverlayType(rawValue: ct) {
                recipe.chartOverlayType = type
            } else if desc.showRoute {
                recipe.chartOverlayType = .route
            } else if desc.showHRChart {
                recipe.chartOverlayType = .hrChart
            }
            if let a = desc.routeAnchorIdx, CardPosition.allCases.indices.contains(a) {
                recipe.routePosition = CardPosition.allCases[a]
            }
            if let ps = desc.pdtSizeID2, let size = TextSizeLevel(rawValue: ps) {
                recipe.pdtSizeLevel = size
            }
            if let de = desc.dataEffectID, let mode = AppearanceMode(rawValue: de) {
                recipe.dataAppearanceMode = mode
            }
            restored.append(recipe)
        }
        return restored
    }

    func deletePhoto(at index: Int) {
        guard index < backgroundPhotos.count else { return }
        if index < photoEntries.count {
            let pe = photoEntries[index]
            OneLinerPhotoStore.delete(mediaRef: pe.mediaRef ?? "")
            modelContext.delete(pe)
            try? modelContext.save()
        }
        let removedText = index < slotTexts.count ? slotTexts[index] : ""
        backgroundPhotos.remove(at: index)
        if index < slotTexts.count { slotTexts.remove(at: index) }
        if !removedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            orphanedTexts.append(removedText)
        }
        if backgroundPhotos.isEmpty {
            photoPickerItems   = []
            selectedPhotoIndex = 0
        } else {
            selectedPhotoIndex = min(selectedPhotoIndex, backgroundPhotos.count - 1)
        }
    }

    @MainActor
    func savePhotos(_ images: [UIImage]) {
        for pe in photoEntries {
            OneLinerPhotoStore.delete(mediaRef: pe.mediaRef ?? "")
            modelContext.delete(pe)
        }
        for (i, img) in images.enumerated() {
            guard let ref = OneLinerPhotoStore.save(img) else { continue }
            let entry = OneLinerEntry(workoutID: workoutID, mediaRef: ref)
            entry.text      = i < slotTexts.count ? slotTexts[i] : ""
            entry.font      = fontChoice
            entry.textColor = textColor
            entry.position  = position
            entry.showDate  = true
            modelContext.insert(entry)
        }
        try? modelContext.save()
    }
}
