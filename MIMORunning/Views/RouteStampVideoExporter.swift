import SwiftUI
import AVFoundation
import MapKit
import CoreLocation

/// 경로 2(카드 전체 지도 + 요약 그리드 스탬프)의 영상 내보내기.
///
/// 경로가 그려지는 동안 스탬프의 **거리·평균 페이스·시간·평균 심박** 네 숫자가 같이 올라간다.
/// 칼로리·케이던스는 시점별 값이 없거나 근사라서 넣지 않는다 — 영상에서는 격자가 페이스·시간·심박 한 줄이다.
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
        /// 좌표별 **시계 시간** 오프셋. 심박 표본과 짝을 맞추려면 시계 시간이어야 한다.
        private let wallOffsets: [TimeInterval]
        /// 좌표별 **실제 달린** 경과 초(일시정지 구간을 뺀 값). 비어 있으면 일정 페이스로 가정한다.
        private let offsets: [TimeInterval]
        /// 멈춘 동안의 표본을 뺀 심박 — 시계 시간 오프셋(오름차순)과 그 앞까지의 합.
        private let hrOffsets: [TimeInterval]
        private let hrPrefixSum: [Int]
        /// 마지막 프레임에 쓸 평균 심박 — 정지 카드와 같은 값이 되도록 HealthKit 값을 그대로 쓴다.
        private let finalAvgHeartRate: Int?

        /// `timeOffsets`는 시계 시간이라 워치에서 멈춘 동안도 흐른다. 실제 달린 시간으로 바꿔 함께 들고 있는다.
        /// 그래야 멈춰 있던 구간에서 시간과 페이스가 같이 멈추고, 끝 값도 총 시간과 맞는다.
        init(coordinates: [CLLocationCoordinate2D], timeOffsets: [TimeInterval],
             pausedSpans: [PausedSpan],
             hrSamples: [(offset: TimeInterval, bpm: Int)],
             finalAvgHeartRate: Int?,
             totalDistanceM: Double, totalDuration: TimeInterval) {
            self.totalDistanceM = totalDistanceM
            self.totalDuration  = totalDuration
            self.finalAvgHeartRate = finalAvgHeartRate
            if timeOffsets.count == coordinates.count {
                self.wallOffsets = timeOffsets
                self.offsets = timeOffsets.map { pausedSpans.activeElapsed(atWallOffset: $0) }
            } else {
                self.wallOffsets = []
                self.offsets = []
            }
            // 멈춘 동안의 심박은 쉬는 심박이라 평균을 끌어내린다 — 빼고 센다
            let usable = hrSamples
                .filter { sample in !pausedSpans.contains { sample.offset >= $0.start && sample.offset < $0.end } }
                .sorted { $0.offset < $1.offset }
            self.hrOffsets = usable.map(\.offset)
            var sums: [Int] = [0]
            sums.reserveCapacity(usable.count + 1)
            for sample in usable { sums.append(sums[sums.count - 1] + sample.bpm) }
            self.hrPrefixSum = sums
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
            return RouteProgressSnapshot(distanceM: totalDistanceM * p,
                                         elapsed: elapsed(at: p),
                                         avgHeartRate: averageHeartRate(at: p))
        }

        /// 진행률 시점까지의 평균 심박 — 페이스와 같은 누적 평균이라 끝에서 러닝 전체의 평균이 된다.
        /// 마지막 프레임은 HealthKit이 준 평균을 그대로 써 정지 카드와 값이 어긋나지 않는다.
        private func averageHeartRate(at p: Double) -> Int? {
            if p >= 1, let final = finalAvgHeartRate { return final }
            guard !hrOffsets.isEmpty else { return finalAvgHeartRate }
            let wall = wallOffset(at: p)
            var lo = 0, hi = hrOffsets.count            // hrOffsets[lo..<hi] 중 wall 이하인 개수를 찾는다
            while lo < hi {
                let mid = (lo + hi) / 2
                if hrOffsets[mid] <= wall { lo = mid + 1 } else { hi = mid }
            }
            // 첫 표본 전이면 첫 값으로 — 칸이 생겼다 없어졌다 하면 스탬프 너비가 흔들린다
            guard lo > 0 else { return hrPrefixSum.count > 1 ? hrPrefixSum[1] : finalAvgHeartRate }
            return Int((Double(hrPrefixSum[lo]) / Double(lo)).rounded())
        }

        /// 진행률(거리)에 해당하는 좌표의 시계 시간. 심박 표본이 시계 시간이라 짝을 맞출 때 쓴다.
        private func wallOffset(at p: Double) -> TimeInterval {
            interpolate(wallOffsets, at: p) ?? (hrOffsets.last ?? 0) * p
        }

        /// 진행률(거리)에 해당하는 좌표를 찾아 그 좌표의 달린 시간을 읽는다.
        /// 오프셋이 없으면 일정 페이스로 본다 — 그래도 총합은 맞는다.
        private func elapsed(at p: Double) -> TimeInterval {
            if p >= 1 { return totalDuration }
            return interpolate(offsets, at: p) ?? totalDuration * p
        }

        /// 누적 거리 비율 p에 해당하는 좌표를 찾아 그 좌표의 값을 선형 보간한다.
        private func interpolate(_ values: [TimeInterval], at p: Double) -> TimeInterval? {
            guard !values.isEmpty, cumFraction.count == values.count, cumFraction.count > 1 else { return nil }
            if p <= 0 { return values[0] }
            if p >= 1 { return values[values.count - 1] }
            var lo = 0, hi = cumFraction.count - 1
            while lo + 1 < hi {
                let mid = (lo + hi) / 2
                if cumFraction[mid] <= p { lo = mid } else { hi = mid }
            }
            let span = cumFraction[hi] - cumFraction[lo]
            let t = span > 0 ? (p - cumFraction[lo]) / span : 0
            return values[lo] + (values[hi] - values[lo]) * t
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
        /// 시점별 심박 — 시계 시간 오프셋. 진행에 따라 올라가는 평균 심박에 쓴다.
        hrSamples: [(offset: TimeInterval, bpm: Int)],
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
                                  hrSamples: hrSamples,
                                  finalAvgHeartRate: activity.avgHeartRate,
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
