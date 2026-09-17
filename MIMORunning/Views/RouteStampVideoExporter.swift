import SwiftUI
import AVFoundation
import MapKit
import CoreLocation

/// 경로 2(카드 전체 지도 + 요약 그리드 스탬프)의 영상 내보내기.
///
/// 경로가 그려지는 동안 스탬프의 **거리·평균 페이스·시간** 세 숫자가 같이 올라간다.
/// 심박·칼로리·케이던스는 시점별 값이 없거나 근사라서 넣지 않는다 — 영상에서는 격자가 세 칸만 나온다.
///
/// 프레임마다 `DetailPanelShareCard`를 그대로 렌더한다(§5.8). 정지 카드와 영상이 같은 뷰라
/// 레이아웃이 갈라질 수 없고, 마지막 프레임은 정지 카드와 같은 그림이 된다.
/// 경로선도 `RouteSnapshotRenderer.draw(progress:)` 한 곳에서 그린다.
@MainActor
enum RouteStampVideoExporter {

    static let fps            = 30
    static let drawSeconds    = 8.0     // 경로가 그려지는 시간
    static let holdSeconds    = 1.5     // 다 그린 뒤 머무는 시간
    static let bitrate        = 8_000_000
    /// 카드 300×375pt를 3.6배로 — 1080×1350(4:5). 인코더가 요구하는 짝수 픽셀.
    static let renderScale: CGFloat = 3.6

    static var cardSize: CGSize {
        CGSize(width: DetailPanelShareCard.cardWidth, height: DetailPanelShareCard.cardHeight)
    }
    static var pixelSize: CGSize {
        CGSize(width: cardSize.width * renderScale, height: cardSize.height * renderScale)
    }

    enum ExportError: Error { case noRoute, snapshotFailed, writerFailed }

    // MARK: - 진행률 → 그 시점의 거리·경과 시간

    /// 좌표 누적 거리와 좌표별 시간 오프셋으로 만든 표.
    /// 진행률은 **거리 기준**이다(경로가 그려진 만큼). 거리는 HealthKit 총거리에 비례 배분해
    /// 마지막 프레임이 정지 카드의 수치와 정확히 같아진다.
    struct ProgressTable {
        let totalDistanceM: Double
        let totalDuration: TimeInterval
        /// 좌표별 누적 거리 비율(0~1)
        private let cumFraction: [Double]
        /// 좌표별 **실제 달린** 경과 초(일시정지 구간을 뺀 값). 비어 있으면 일정 페이스로 가정한다.
        private let offsets: [TimeInterval]

        /// `timeOffsets`는 시계 시간이라 워치에서 멈춘 동안도 흐른다. 여기서 실제 달린 시간으로 바꿔 둔다.
        /// 그래야 멈춰 있던 구간에서 시간과 페이스가 같이 멈추고, 끝 값도 총 시간과 맞는다.
        init(coordinates: [CLLocationCoordinate2D], timeOffsets: [TimeInterval],
             pausedSpans: [PausedSpan],
             totalDistanceM: Double, totalDuration: TimeInterval) {
            self.totalDistanceM = totalDistanceM
            self.totalDuration  = totalDuration
            if timeOffsets.count == coordinates.count {
                self.offsets = timeOffsets.map { pausedSpans.activeElapsed(atWallOffset: $0) }
            } else {
                self.offsets = []
            }
            guard coordinates.count > 1 else { self.cumFraction = [0]; return }
            var cum: [Double] = [0]
            cum.reserveCapacity(coordinates.count)
            for i in 1..<coordinates.count {
                let a = CLLocation(latitude: coordinates[i - 1].latitude, longitude: coordinates[i - 1].longitude)
                let b = CLLocation(latitude: coordinates[i].latitude,     longitude: coordinates[i].longitude)
                cum.append(cum[i - 1] + a.distance(from: b))
            }
            let total = cum.last ?? 0
            self.cumFraction = total > 0 ? cum.map { $0 / total } : cum.map { _ in 0 }
        }

        func snapshot(at progress: Double) -> RouteProgressSnapshot {
            let p = max(0, min(1, progress))
            return RouteProgressSnapshot(distanceM: totalDistanceM * p, elapsed: elapsed(at: p))
        }

        /// 진행률(거리)에 해당하는 좌표를 찾아 그 좌표의 경과 초를 읽는다.
        /// 오프셋이 없으면 일정 페이스로 본다 — 그래도 총합은 맞는다.
        private func elapsed(at p: Double) -> TimeInterval {
            guard !offsets.isEmpty, cumFraction.count == offsets.count, cumFraction.count > 1 else {
                return totalDuration * p
            }
            if p <= 0 { return 0 }
            if p >= 1 { return totalDuration }
            var lo = 0, hi = cumFraction.count - 1
            while lo + 1 < hi {
                let mid = (lo + hi) / 2
                if cumFraction[mid] <= p { lo = mid } else { hi = mid }
            }
            let span = cumFraction[hi] - cumFraction[lo]
            let t = span > 0 ? (p - cumFraction[lo]) / span : 0
            return offsets[lo] + (offsets[hi] - offsets[lo]) * t
        }
    }

    // MARK: - 내보내기

    static func export(
        activity: Activity,
        detail: ActivityDetail?,
        condition: ActivityCondition?,
        age: Int?,
        isMale: Bool?,
        placeName: String?,
        segmentColors: [UIColor]?,
        onProgress: @escaping (Double) -> Void
    ) async throws -> URL {

        // 좌표와 시간 오프셋을 같은 판정으로 함께 걸러야 인덱스가 어긋나지 않는다
        let rawCoords  = detail?.routeCoordinates ?? []
        let rawOffsets = detail?.routeTimeOffsets ?? []
        let keep = rawCoords.indices.filter { RouteSnapshotRenderer.isValid(rawCoords[$0]) }
        let coords  = keep.map { rawCoords[$0] }
        let offsets = rawOffsets.count == rawCoords.count ? keep.map { rawOffsets[$0] } : []
        guard coords.count > 1 else { throw ExportError.noRoute }

        // 지도 스냅샷은 정지 카드와 같은 설정 — 다크 standard · POI 제외 · 경로는 위 60%
        guard let opts = RouteSnapshotRenderer.options(
            coordinates: coords,
            size: cardSize,
            scale: renderScale,
            routeBottomLimit: DetailPanelShareCard.mapRouteBottomLimit
        ) else { throw ExportError.snapshotFailed }
        opts.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        opts.mapType = .standard
        opts.pointOfInterestFilter = .excludingAll
        guard let snap = try? await MKMapSnapshotter(options: opts).start() else {
            throw ExportError.snapshotFailed
        }

        let table = ProgressTable(coordinates: coords, timeOffsets: offsets,
                                  pausedSpans: detail?.pausedSpans ?? [],
                                  totalDistanceM: activity.distance,
                                  totalDuration: activity.duration)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo_route3_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)

        let px = pixelSize
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey:  AVVideoCodecType.h264,
            AVVideoWidthKey:  Int(px.width),
            AVVideoHeightKey: Int(px.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoProfileLevelKey:   AVVideoProfileLevelH264HighAutoLevel
            ]
        ])
        videoIn.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoIn,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey  as String: Int(px.width),
                kCVPixelBufferHeightKey as String: Int(px.height)
            ]
        )
        writer.add(videoIn)
        guard writer.startWriting() else { throw ExportError.writerFailed }
        writer.startSession(atSourceTime: .zero)

        let animFrames  = Int(drawSeconds * Double(fps))
        let holdFrames  = Int(holdSeconds * Double(fps))
        let totalFrames = animFrames + holdFrames

        defer { onProgress(1) }

        for frameIdx in 0..<totalFrames {
            try Task.checkCancellation()

            let p: Double = frameIdx < animFrames
                ? Double(frameIdx) / Double(max(1, animFrames - 1))
                : 1

            // isReadyForMoreMediaData 대기는 autoreleasepool 밖에서 — 안에서 await할 수 없다
            while !videoIn.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }

            // 프레임마다 생기는 지도·카드 이미지를 즉시 버린다. 없으면 285프레임 × 수 MB가 쌓여 메모리로 죽는다.
            _ = autoreleasepool { () -> Bool in
                let mapImage = RouteSnapshotRenderer.draw(
                    on: snap, coordinates: coords, segmentColors: segmentColors,
                    lineScale: 1, showKmMarkers: false, progress: p)

                let card = DetailPanelShareCard(
                    activity: activity, detail: detail, activePanel: .map,
                    hrSamples: [], panelSeriesData: [],
                    mapSnapshot: mapImage,
                    condition: condition, age: age, isMale: isMale,
                    theme: .dark, placeName: placeName,
                    routeStyle: .stamp,
                    routeProgress: table.snapshot(at: p)
                )
                .frame(width: cardSize.width, height: cardSize.height)

                let renderer = ImageRenderer(content: card)
                renderer.scale = renderScale
                guard let frame = renderer.uiImage,
                      let buffer = RunChartReplayExporter.pixelBuffer(from: frame, size: px)
                else { return false }

                let pts = CMTime(value: CMTimeValue(frameIdx), timescale: CMTimeScale(fps))
                return adaptor.append(buffer, withPresentationTime: pts)
            }

            onProgress(Double(frameIdx + 1) / Double(totalFrames))
        }

        videoIn.markAsFinished()
        await withCheckedContinuation { cont in writer.finishWriting { cont.resume() } }
        guard writer.status == .completed else { throw ExportError.writerFailed }
        return outputURL
    }
}

/// 경로 2의 결과물 — 정지 이미지 / 영상.
enum StampOutputMode { case image, video }
