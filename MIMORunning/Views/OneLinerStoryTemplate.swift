// OneLiner 카드 — 스토리·슬라이드 클립 편집 헬퍼
//
// ClipTrimSheet 연동: storyPhotos → [ClipRecipe] 변환 및 편집 결과 → SwiftData 저장.
// ShareCardView.swift에서 추출. extension ShareCardScreen 으로 타입 상태에 직접 접근.

import SwiftUI
import SwiftData

extension ShareCardScreen {

    // MARK: - Story clip edit helpers

    /// storyPhotos를 ClipTrimSheet에 전달할 ClipRecipe 배열로 변환.
    /// 기존 OneLinerEntry에서 text/style 복원, 없으면 기본값.
    func makeStoryClipRecipes(isSlide: Bool = false) -> [ClipRecipe] {
        let photos = storyPhotos
        let prefix = isSlide ? "slide:" : "photo:"
        return photos.enumerated().map { i, photo in
            let uuid = i < oneLinerVM.storyPhotoUUIDs.count ? oneLinerVM.storyPhotoUUIDs[i] : UUID().uuidString
            let ref  = "\(prefix)\(uuid)"
            // slide: prefix가 없으면 photo: 기존 항목으로 폴백 (마이그레이션 경로)
            let entry = oneLinerEntries.first { $0.mediaRef == ref }
                     ?? (isSlide ? oneLinerEntries.first { $0.mediaRef == "photo:\(uuid)" } : nil)
            var recipe = ClipRecipe(
                url: URL(fileURLWithPath: "/dev/null"),
                fullDuration: 3.0,
                thumbnail: photo
            )
            recipe.storedPhotoRef = ref
            if let e = entry {
                if e.text.hasPrefix("v3slide\n"),
                   let data = e.text.dropFirst("v3slide\n".count).data(using: .utf8),
                   let desc = try? JSONDecoder().decode(SavedClipDescriptor.self, from: data) {
                    // 신규 포맷: 모든 스타일 (plateOn·sizeLevel·effectID 포함) 완전 복원
                    recipe.lines      = desc.lines.map { line in
                        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if t.hasPrefix("v3slide") || t.hasPrefix("v3recipes")
                            || t.hasPrefix("v4recipes") || t.hasPrefix("v2clips")
                            || (t.count > 30 && t.hasPrefix("{") && t.hasSuffix("}")) { return "" }
                        return line
                    }
                    recipe.fontChoice = OneLinerFont.migrate(desc.fontID)
                    recipe.textColor  = desc.colorID.flatMap { OneLinerTextColor(rawValue: $0) } ?? .white
                    if let idx = desc.anchorIdx, CardPosition.allCases.indices.contains(idx) {
                        recipe.position = CardPosition.allCases[idx]
                    }
                    recipe.sizeLevel = desc.sizeID.flatMap { TextSizeLevel(rawValue: $0) } ?? .large
                    if let eid = desc.effectID, eid.contains("|") {
                        let parts = eid.split(separator: "|", maxSplits: 3).map(String.init)
                        recipe.appearanceMode = parts.count > 0 ? (AppearanceMode(rawValue: parts[0]) ?? .typing) : .typing
                        recipe.decorEffect    = parts.count > 1 ? (DecorEffect(rawValue: parts[1]) ?? .none) : .none
                        if parts.count > 2 {
                            recipe.hasBorder = parts[2].contains("B1")
                            recipe.plateOn   = parts[2].contains("P1")
                        }
                        recipe.flyDirection = parts.count > 3 ? (FlyInDirection(rawValue: parts[3]) ?? .trailing) : .trailing
                    }
                    recipe.plateColorPreset = desc.plateColorID.flatMap { PlateColorPreset(rawValue: $0) } ?? .blackWhite
                    recipe.metricPace      = desc.metricPace
                    recipe.metricDistance  = desc.metricDistance
                    recipe.metricTime      = desc.metricTime
                    recipe.metricHeartRate = desc.metricHeartRate
                    if let idx = desc.pdtAnchorIdx, CardPosition.allCases.indices.contains(idx) {
                        recipe.pdtPosition = CardPosition.allCases[idx]
                    }
                    if let ct = desc.chartTypeID, let type = ChartOverlayType(rawValue: ct) {
                        recipe.chartOverlayType = type
                    } else if desc.showRoute {
                        recipe.chartOverlayType = .route
                    } else if desc.showHRChart {
                        recipe.chartOverlayType = .hrChart
                    }
                    if let idx = desc.routeAnchorIdx, CardPosition.allCases.indices.contains(idx) {
                        recipe.routePosition = CardPosition.allCases[idx]
                    }
                    if let ps = desc.pdtSizeID2, let size = TextSizeLevel(rawValue: ps) {
                        recipe.pdtSizeLevel = size
                    }
                    if let de = desc.dataEffectID, let mode = AppearanceMode(rawValue: de) {
                        recipe.dataAppearanceMode = mode
                    }
                    // 사진 클립 재생 시간 복원 (3/4/5초 사용자 선택값)
                    recipe.fullDuration = desc.fullDuration
                    recipe.trimStart    = desc.trimStart
                    recipe.trimEnd      = desc.trimEnd
                    recipe.cropOffsetX  = CGFloat(desc.cropOffsetX)
                } else {
                    // 구 포맷: 텍스트 + 기본 3개 스타일만 복원 (마이그레이션 경로)
                    var lines = e.text.components(separatedBy: "\n")
                    while lines.count < 2 { lines.append("") }
                    recipe.lines      = Array(lines.prefix(2))
                    recipe.fontChoice = e.font
                    recipe.textColor  = e.textColor
                    recipe.position   = e.position
                }
            } else {
                recipe.lines = ["", ""]
            }
            return recipe
        }
    }

    /// ClipTrimSheet 완료 후 편집 결과를 OneLinerEntry에 저장.
    /// plateOn·sizeLevel·effectID 등 전체 스타일을 SavedClipDescriptor JSON("v3slide\n")으로 인코딩.
    func saveStoryClipEdits(_ recipes: [ClipRecipe], isSlide: Bool = false) {
        let prefix = isSlide ? "slide:" : "photo:"
        for (i, recipe) in recipes.enumerated() {
            guard i < oneLinerVM.storyPhotoUUIDs.count else { continue }
            let ref  = "\(prefix)\(oneLinerVM.storyPhotoUUIDs[i])"
            let text = recipe.lines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            // SavedClipDescriptor JSON으로 전체 스타일 직렬화 (쉬는 날 buildRecipeSet과 동일 포맷)
            let cleanLines = recipe.lines.map { line -> String in
                let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.hasPrefix("v3slide") || t.hasPrefix("v3recipes")
                    || t.hasPrefix("v4recipes") || t.hasPrefix("v2clips")
                    || (t.count > 30 && t.hasPrefix("{") && t.hasSuffix("}")) { return "" }
                return line
            }
            let desc = SavedClipDescriptor(
                assetID: nil, clipVideoRef: nil,
                photoRef: recipe.storedPhotoRef, thumbRef: recipe.thumbRef,
                trimStart: recipe.trimStart, trimEnd: recipe.trimEnd,
                fullDuration: recipe.fullDuration,
                lines: cleanLines,
                fontID: recipe.fontChoice.rawValue,
                colorID: recipe.textColor.rawValue,
                anchorIdx: CardPosition.allCases.firstIndex(of: recipe.position),
                sizeID: recipe.sizeLevel.rawValue,
                effectID: "\(recipe.appearanceMode.rawValue)|\(recipe.decorEffect.rawValue)|B\(recipe.hasBorder ? 1 : 0)P\(recipe.plateOn ? 1 : 0)|\(recipe.flyDirection.rawValue)",
                plateColorID: recipe.plateColorPreset.rawValue,
                speed: recipe.speed, cropOffsetX: Double(recipe.cropOffsetX),
                metricPace: recipe.metricPace,
                metricDistance: recipe.metricDistance,
                metricTime: recipe.metricTime,
                metricHeartRate: recipe.metricHeartRate,
                pdtAnchorIdx: CardPosition.allCases.firstIndex(of: recipe.pdtPosition),
                showRoute: recipe.showRoute,
                routeAnchorIdx: CardPosition.allCases.firstIndex(of: recipe.routePosition),
                showHRChart: recipe.showHRChart,
                chartTypeID:  recipe.chartOverlayType == .none ? nil : recipe.chartOverlayType.rawValue,
                pdtSizeID2:   recipe.pdtSizeLevel.rawValue,
                dataEffectID: recipe.dataAppearanceMode.rawValue
            )
            let payload: String
            if let data = try? JSONEncoder().encode(desc),
               let json = String(data: data, encoding: .utf8) {
                payload = "v3slide\n" + json
            } else {
                payload = text
            }

            let hasMetric = recipe.metricPace || recipe.metricDistance || recipe.metricTime
                          || recipe.metricHeartRate || recipe.chartOverlayType != .none
            let hasDurationChange = abs(recipe.trimEnd - PhotoSlideComposition.photoDuration) > 0.01
            let hasCropChange     = abs(recipe.cropOffsetX - 0.5) > 0.001
            let shouldSave = !text.isEmpty || hasMetric || hasDurationChange || hasCropChange

            if let existing = oneLinerEntries.first(where: { $0.mediaRef == ref }) {
                if shouldSave {
                    existing.text      = payload
                    existing.font      = recipe.fontChoice
                    existing.textColor = recipe.textColor
                    existing.position  = recipe.position
                } else {
                    modelContext.delete(existing)
                }
            } else if shouldSave {
                let entry = OneLinerEntry(workoutID: activity.id.uuidString, mediaRef: ref)
                entry.text      = payload
                entry.font      = recipe.fontChoice
                entry.textColor = recipe.textColor
                entry.position  = recipe.position
                entry.showDate  = true
                modelContext.insert(entry)
            }
        }
        oneLinerVM.cachedStoryRecipes = recipes  // @Query 갱신 전 즉시 렌더용 캐시
        try? modelContext.save()
        Task { await renderCard() }
        // 편집 완료 후 미리보기는 수동(▶ 버튼)으로 시작 — 자동 buildPreview 호출 없음
        if template == .slide { previewPlayer.invalidate() }
    }
}
