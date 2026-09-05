import SwiftUI
import AVFoundation
import UIKit

// MARK: - RestDayOneLinerSheet + Preview & Export

extension RestDayOneLinerSheet {

    func buildPreview() {
        guard !previewPlayer.isBuilding else { return }
        Task {
            if selectedTemplate == .video {
                // 영상 모드: PHAsset 재해석 후 AVPlayer 경로 (export와 동일 함수)
                var resolved = clipRecipes
                for i in resolved.indices {
                    guard resolved[i].resolvedAsset == nil,
                          !FileManager.default.fileExists(atPath: resolved[i].url.path),
                          let assetID = resolved[i].assetIdentifier else { continue }
                    do {
                        resolved[i].resolvedAsset = try await MultiClipComposition.resolveAVAsset(assetID: assetID)
                    } catch { }
                }
                await previewPlayer.buildForVideoClips(
                    recipes: resolved, muteAudio: muteVideoAudio,
                    routeCoords: routeCoords, hrSamples: hrSamples, splits: splits,
                    chartSeriesData: chartSeriesData, hrZones: hrZones, intervalSegments: intervalSegments,
                    videoTitle: videoTitle, titleStyle: titleStyle,
                    safeTopOverride: 1920 * 0.06, safeBotOverride: 1920 * 0.06,
                    wordmarkTopPad: 1920 * 0.06)
            } else {
                // 슬라이드·스토리: 썸네일 기반 슬라이드 미리보기
                let photos = clipRecipes.compactMap { $0.thumbnail }
                guard !photos.isEmpty else { return }
                await previewPlayer.buildForPhotoSlides(
                    photos: photos, recipes: clipRecipes,
                    hrSamples: hrSamples, splits: splits,
                    chartSeriesData: chartSeriesData, hrZones: hrZones, intervalSegments: intervalSegments,
                    videoTitle: videoTitle, titleStyle: titleStyle)
            }
        }
    }

    @MainActor
    func renderCardForSharing() {
        // 스토리 템플릿: 클립 사진별 정지 카드 렌더링
        if selectedTemplate == .story, !clipRecipes.isEmpty {
            FontLoader.registerBundledFonts()
            var rendered: [UIImage] = []
            for recipe in clipRecipes {
                guard let photo = recipe.thumbnail else { continue }
                let txt = recipe.lines
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: "\n")
                let card = OneLinerCard(
                    backgroundPhoto: photo,
                    text: txt,
                    position: recipe.position,
                    textColor: recipe.textColor,
                    fontChoice: recipe.fontChoice,
                    sizeLevel: recipe.sizeLevel,
                    appearanceMode: recipe.appearanceMode,
                    decorEffect: recipe.decorEffect,
                    hasBorder: recipe.hasBorder,
                    captionMode: true
                )
                .frame(width: OneLinerCard.cardWidth, height: OneLinerCard.cardHeight)
                let renderer = ImageRenderer(content: card)
                renderer.scale = 3.0
                if let img = renderer.uiImage { rendered.append(img) }
            }
            if !rendered.isEmpty {
                markAsShared()
                presentShareSheet(images: rendered)
            }
            return
        }

        // 영상/슬라이드 템플릿: VideoExportService로 실제 .mov 출력
        if (selectedTemplate == .video || selectedTemplate == .slide), !clipRecipes.isEmpty {
            isExportingVideo = true
            Task {
                defer { isExportingVideo = false }
                do {
                    var recipes = clipRecipes

                    // Resolve recipe URLs that expired (temp files from previous session)
                    var tempURLsToClean: [URL] = []
                    for i in recipes.indices {
                        guard !FileManager.default.fileExists(atPath: recipes[i].url.path) else { continue }
                        if let assetID = recipes[i].assetIdentifier {
                            recipes[i].resolvedAsset = try await MultiClipComposition.resolveAVAsset(assetID: assetID)
                        } else if let pr = recipes[i].storedPhotoRef,
                                  let img = OneLinerPhotoStore.load(mediaRef: pr) {
                            let tmpURL = FileManager.default.temporaryDirectory
                                .appendingPathComponent("mimo_photoclip_\(UUID().uuidString).jpg")
                            if let d = img.jpegData(compressionQuality: 0.82) { try d.write(to: tmpURL) }
                            recipes[i].url = tmpURL
                            if recipes[i].thumbnail == nil { recipes[i].thumbnail = img }
                            tempURLsToClean.append(tmpURL)
                        } else {
                            throw RestDayExportError.clipNotFound
                        }
                    }
                    defer { tempURLsToClean.forEach { try? FileManager.default.removeItem(at: $0) } }

                    if isPhotoSlideMode {
                        // Photo slide: single-pass CALayer composite (Ken Burns + text)
                        let photos = recipes.compactMap { $0.thumbnail }
                        guard !photos.isEmpty else { return }
                        let outputURL = try await PhotoSlideComposition.exportSlideWithText(
                            photos: photos, recipes: recipes,
                            metricLookup: metricLookup,
                            hrSamples: hrSamples, splits: splits,
                            chartSeriesData: chartSeriesData, hrZones: hrZones, intervalSegments: intervalSegments,
                            videoTitle: videoTitle, titleStyle: titleStyle)
                        markAsShared()
                        presentShareSheet(url: outputURL)
                    } else {
                        // Video clips: multi-clip compose or single-pass
                        let hasResolvedAssets = recipes.contains { $0.resolvedAsset != nil }
                        let needsCompose = recipes.count > 1 || recipes.contains { $0.isTrimmed } || hasResolvedAssets
                            || recipes.contains { abs($0.speed - 1.0) > 0.01 }
                        let exportURL:  URL
                        var cleanupURL: URL? = nil
                        if needsCompose {
                            let (composed, _) = try await MultiClipComposition.composeAndExport(
                                recipes: recipes, muteAudio: muteVideoAudio)
                            exportURL  = composed
                            cleanupURL = composed
                        } else {
                            exportURL = recipes[0].url
                        }
                        defer { cleanupURL.map { try? FileManager.default.removeItem(at: $0) } }

                        let isMuted = muteVideoAudio
                        let outputURL = try await VideoExportService.exportOneLinerClipBoundVideo(
                            sourceURL: exportURL,
                            recipes: recipes,
                            muteAudio: isMuted,
                            metricLookup: metricLookup,
                            routeCoords: routeCoords, hrSamples: hrSamples, splits: splits,
                            hrZones: hrZones, intervalSegments: intervalSegments, chartSeriesData: chartSeriesData,
                            videoTitle: videoTitle, titleStyle: titleStyle)
                        markAsShared()
                        presentShareSheet(url: outputURL)
                    }
                } catch RestDayExportError.clipNotFound {
                    exportError = AppLanguage.shared.s(
                        "영상 파일을 찾을 수 없습니다. 영상을 삭제하고 다시 추가해주세요.",
                        "Video file not found. Please remove the clip and add it again.")
                } catch {
                    exportError = AppLanguage.shared.s(
                        "내보내기 중 오류가 발생했습니다: \(error.localizedDescription)",
                        "Export error: \(error.localizedDescription)")
                }
            }
            return
        }

        // 사진/그라데이션 템플릿: ImageRenderer로 정지 이미지 공유
        FontLoader.registerBundledFonts()
        let pairs: [(UIImage?, String)] = backgroundPhotos.count >= 2
            ? backgroundPhotos.enumerated().map { i, photo in
                  (photo, i < slotTexts.count ? slotTexts[i] : "")
              }
            : [(cardBackground, cardText)]

        var rendered: [UIImage] = []
        for (i, (photo, txt)) in pairs.enumerated() {
            let rp = i < clipRecipes.count ? clipRecipes[i] : nil
            let card = OneLinerCard(
                backgroundPhoto: photo,
                text: txt,
                position: position,
                textColor: textColor,
                fontChoice: fontChoice,
                hasBorder: rp?.hasBorder ?? previewHasBorder,
                captionMode: true
            )
            .frame(width: OneLinerCard.cardWidth, height: OneLinerCard.cardHeight)
            let renderer = ImageRenderer(content: card)
            renderer.scale = 3.0
            if let img = renderer.uiImage { rendered.append(img) }
        }
        guard !rendered.isEmpty else { return }
        presentShareSheet(images: rendered)
    }

    func presentShareSheet(url: URL) {
        presentActivityController(items: [url])
    }

    func presentShareSheet(images: [UIImage]) {
        presentActivityController(items: images)
    }

    func presentActivityController(items: [Any]) {
        // Delay to let the SwiftUI state update (isExportingVideo = false from defer)
        // settle before UIKit presents, otherwise the first presentation is swallowed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let root = windowScene.windows.first?.rootViewController else { return }
            var top = root
            while let next = top.presentedViewController { top = next }
            if let pop = vc.popoverPresentationController {
                pop.sourceView = top.view
                pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            }
            top.present(vc, animated: true)
        }
    }
}
