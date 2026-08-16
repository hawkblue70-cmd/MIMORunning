// OneLiner 카드 — 영상 클립 저장·복원·일괄 내보내기
//
// 영상 템플릿(.video) 전용 SwiftData 클립 직렬화 및 일괄 내보내기.
// ShareCardView.swift에서 추출. extension ShareCardScreen 으로 타입 상태에 직접 접근.

import SwiftUI
import SwiftData
import AVFoundation

extension ShareCardScreen {

    // MARK: - OneLiner 클립 저장/복원 (영상 템플릿 전용)

    private var oneLinerClipsEntry: OneLinerEntry? {
        oneLinerEntries.first { $0.mediaRef == "oneliner:clips" }
    }

    func saveOneLinerClipRecipes() {
        let validRecipes = oneLinerVM.oneLinerClipRecipes.filter {
            $0.assetIdentifier != nil || $0.clipVideoRef != nil || $0.storedPhotoRef != nil
        }
        if validRecipes.isEmpty && oneLinerVM.oneLinerVideoTitle.isEmpty {
            if let entry = oneLinerClipsEntry {
                modelContext.delete(entry)
                try? modelContext.save()
            }
            return
        }
        let descs = validRecipes.map { r in
            SavedClipDescriptor(
                assetID: r.assetIdentifier, clipVideoRef: r.clipVideoRef,
                photoRef: r.storedPhotoRef, thumbRef: r.thumbRef,
                trimStart: r.trimStart, trimEnd: r.trimEnd, fullDuration: r.fullDuration,
                lines: r.lines,
                fontID: r.fontChoice.rawValue, colorID: r.textColor.rawValue,
                anchorIdx: CardPosition.allCases.firstIndex(of: r.position),
                sizeID: r.sizeLevel.rawValue,
                effectID: "\(r.appearanceMode.rawValue)|\(r.decorEffect.rawValue)|B\(r.hasBorder ? 1 : 0)|\(r.flyDirection.rawValue)",
                speed: r.speed,
                cropOffsetX: Double(r.cropOffsetX),
                metricPace: r.metricPace, metricDistance: r.metricDistance, metricTime: r.metricTime,
                metricHeartRate: r.metricHeartRate,
                pdtAnchorIdx: CardPosition.allCases.firstIndex(of: r.pdtPosition),
                showRoute: r.showRoute,
                routeAnchorIdx: CardPosition.allCases.firstIndex(of: r.routePosition),
                showHRChart: r.showHRChart,
                chartTypeID:  r.chartOverlayType == .none ? nil : r.chartOverlayType.rawValue,
                pdtSizeID2:   r.pdtSizeLevel.rawValue,
                dataEffectID: r.dataAppearanceMode.rawValue)
        }
        let saved = SavedRecipeSet(
            isPhotoSlide: false, muteAudio: oneLinerVM.oneLinerMuteAudio, clips: descs,
            videoTitle: oneLinerVM.oneLinerVideoTitle,
            titleAnchorIdx: CardPosition.allCases.firstIndex(of: oneLinerVM.oneLinerTitleStyle.position),
            titleFontID: oneLinerVM.oneLinerTitleStyle.fontChoice.rawValue,
            titleColorID: oneLinerVM.oneLinerTitleStyle.textColor.rawValue,
            titleSizeID: oneLinerVM.oneLinerTitleStyle.sizeLevel.rawValue,
            titleOutline: oneLinerVM.oneLinerTitleStyle.outline)
        guard let data = try? JSONEncoder().encode(saved),
              let json = String(data: data, encoding: .utf8) else { return }
        let payload = "v4recipes\n" + json
        if let existing = oneLinerClipsEntry {
            existing.text = payload
        } else {
            let entry = OneLinerEntry(workoutID: activity.id.uuidString, mediaRef: "oneliner:clips")
            entry.text = payload
            modelContext.insert(entry)
        }
        try? modelContext.save()
    }

    func loadOneLinerClipRecipes() {
        guard let entry = oneLinerClipsEntry,
              entry.text.hasPrefix("v4recipes\n"),
              let data = entry.text.dropFirst("v4recipes\n".count).data(using: .utf8),
              let saved = try? JSONDecoder().decode(SavedRecipeSet.self, from: data) else { return }
        oneLinerVM.oneLinerMuteAudio  = saved.muteAudio
        oneLinerVM.oneLinerVideoTitle = saved.videoTitle
        var style = OneLinerTitleStyle()
        if let idx = saved.titleAnchorIdx, CardPosition.allCases.indices.contains(idx) {
            style.position = CardPosition.allCases[idx]
        }
        if let fid = saved.titleFontID  { style.fontChoice = OneLinerFont.migrate(fid) }
        if let cid = saved.titleColorID { style.textColor  = OneLinerTextColor(rawValue: cid) ?? .white }
        if let sid = saved.titleSizeID  { style.sizeLevel  = TextSizeLevel(rawValue: sid) ?? .medium }
        style.outline = saved.titleOutline
        oneLinerVM.oneLinerTitleStyle = style
        guard !saved.clips.isEmpty else { return }
        var restored: [ClipRecipe] = []
        for desc in saved.clips {
            let thumb: UIImage?
            if let pr = desc.photoRef { thumb = OneLinerPhotoStore.load(mediaRef: pr) }
            else if let tr = desc.thumbRef { thumb = ClipThumbStore.load(ref: tr) }
            else { thumb = nil }
            let recipeURL: URL
            if let ref = desc.clipVideoRef,
               let stableURL = ClipVideoStore.fileURL(ref: ref),
               FileManager.default.fileExists(atPath: stableURL.path) {
                recipeURL = stableURL
            } else {
                recipeURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("mimo_placeholder_\(UUID().uuidString)")
            }
            var recipe = ClipRecipe(url: recipeURL, fullDuration: desc.fullDuration, thumbnail: thumb)
            recipe.trimStart       = desc.trimStart
            recipe.trimEnd         = desc.trimEnd
            recipe.lines           = desc.lines.map { line in
                let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.hasPrefix("v3slide") || t.hasPrefix("v3recipes")
                    || t.hasPrefix("v4recipes") || t.hasPrefix("v2clips")
                    || (t.count > 30 && t.hasPrefix("{") && t.hasSuffix("}")) { return "" }
                return line
            }
            recipe.assetIdentifier = desc.assetID
            recipe.clipVideoRef    = desc.clipVideoRef
            recipe.storedPhotoRef  = desc.photoRef
            recipe.thumbRef        = desc.thumbRef
            recipe.fontChoice      = OneLinerFont.migrate(desc.fontID)
            recipe.textColor       = desc.colorID.flatMap { OneLinerTextColor(rawValue: $0) } ?? oneLinerVM.oneLinerColor
            if let idx = desc.anchorIdx, CardPosition.allCases.indices.contains(idx) {
                recipe.position = CardPosition.allCases[idx]
            } else {
                recipe.position = oneLinerVM.oneLinerPosition
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
            recipe.speed            = desc.speed
            recipe.cropOffsetX      = CGFloat(desc.cropOffsetX)
            recipe.metricPace       = desc.metricPace
            recipe.metricDistance   = desc.metricDistance
            recipe.metricTime       = desc.metricTime
            recipe.metricHeartRate  = desc.metricHeartRate
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
        oneLinerVM.oneLinerVideoModeRecipes = restored
        // 이미 세션 내 클립이 있으면 SwiftData 재로딩으로 순서를 덮어쓰지 않음
        if oneLinerVM.oneLinerClipRecipes.isEmpty {
            if template == .video { oneLinerVM.oneLinerClipRecipes = restored }
        }
        // videoPreviewImage는 OneLiner 영상 탭에서만 적용 — 슬라이드·스토리 탭에서는 표시 안 함
        if isOneLiner, template == .video, let firstThumb = restored.first?.thumbnail {
            videoPreviewImage = firstThumb
        }
    }

    func syncOneLinerVideoBacking(from oldTemplate: ShareTemplate, to newTemplate: ShareTemplate) {
        guard isOneLiner else { return }
        // 비디오 템플릿을 벗어날 때: active clips → 백업, active 비움, 썸네일 제거
        if oldTemplate == .video {
            oneLinerVM.oneLinerVideoModeRecipes = oneLinerVM.oneLinerClipRecipes
            oneLinerVM.oneLinerClipRecipes = []
            videoPreviewImage = nil
        }
        // 비디오 템플릿으로 돌아올 때: 백업에서 복원 + 썸네일 갱신
        if newTemplate == .video {
            oneLinerVM.oneLinerClipRecipes = oneLinerVM.oneLinerVideoModeRecipes
            if let thumb = oneLinerVM.oneLinerVideoModeRecipes.first?.thumbnail {
                videoPreviewImage = thumb
            }
        }
    }

    // MARK: - 일괄 렌더링 → 공유 시트

    /// 문구가 연결된 사진을 순서대로 렌더링한 뒤 공유 시트를 표시한다.
    @MainActor
    func batchExportOneLinerCards() async {
        guard isOneLiner, template == .story else { return }
        isBatchExporting = true
        defer { isBatchExporting = false }

        var rendered: [UIImage] = []
        for i in oneLinerVM.storyPhotoUUIDs.indices {
            guard i < storyPhotos.count else { continue }
            // 내보내기 시점엔 @Query 갱신 완료 — photoRecipe 사용
            guard let pr = photoRecipe(at: i, prefix: "photo:") else { continue }
            let hasText    = pr.lines.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let hasMetrics = pr.metricPace || pr.metricDistance || pr.metricTime || pr.metricHeartRate
            let hasChart   = pr.showRoute || pr.showHRChart || pr.chartOverlayType != .none
            guard hasText || hasMetrics || hasChart else { continue }

            let text  = pr.lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n")
            let photo = oneLinerVM.highQualityStoryPhotos[i] ?? storyPhotos[i]
            let card = OneLinerCard(
                activity: activity,
                backgroundPhoto: photo,
                cropOffsetX: pr.cropOffsetX,
                text: text,
                position: pr.position,
                textColor: pr.textColor,
                fontChoice: pr.fontChoice,
                sizeLevel: pr.sizeLevel,
                appearanceMode: pr.appearanceMode,
                decorEffect: pr.decorEffect,
                hasBorder: pr.hasBorder,
                showDate: oneLinerVM.oneLinerShowDate,
                captionMode: true,
                chartBottomReserved: storyChartBottomReserved(for: pr),
                isStaticPreview: true,   // ImageRenderer는 onAppear/애니 없이 초기 상태만 캡처 → 즉시 표시 필요
                metricPace: pr.metricPace,
                metricDistance: pr.metricDistance,
                metricTime: pr.metricTime,
                metricHeartRate: pr.metricHeartRate,
                pdtPosition: pr.pdtPosition,
                pdtSizeLevel: pr.pdtSizeLevel,
                availableMetrics: oneLinerAvailableMetrics,
                showRoute: pr.showRoute,
                routeCoords: routeCoords,
                routePosition: pr.routePosition,
                showHRChart: pr.showHRChart,
                hrSamples: shareHRSamples,
                hrZones: detail?.hrZones ?? [],
                chartOverlayType: pr.chartOverlayType,
                chartSeriesData: chartSeriesData,
                chartSplits: detail?.splits ?? [],
                intervalSegments: detail?.intervalSegments ?? []
            )
            let renderer = ImageRenderer(content: card.frame(width: OneLinerCard.cardWidth,
                                                              height: OneLinerCard.cardHeight))
            renderer.scale = 3
            if let img = renderer.uiImage { rendered.append(img) }
            // 프레임 간 렌더러 충돌 방지
            await Task.yield()
        }
        if !rendered.isEmpty {
            storyShareImages = rendered
            showShareSheet   = true
        }
    }
}
