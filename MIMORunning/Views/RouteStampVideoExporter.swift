import SwiftUI
import AVFoundation
import MapKit
import CoreLocation

/// 경로 1(카드 전체 지도 + 요약 그리드 스탬프)의 영상 내보내기.
///
/// 경로가 8~12초(거리에 따라) 동안 그려지고, 스탬프의 **거리·평균 페이스·시간·심박** 네 숫자가 같이 움직인다.
/// 심박만 그 시점의 값(순간)이고 나머지는 누적이다. 심박 숫자는 그 시점 존 색으로 칠해져
/// 경로선의 그 지점 색과 같아진다.
/// 칼로리·케이던스는 시점별 값이 없거나 근사라서 넣지 않는다 — 영상에서는 격자가 페이스·시간·심박 한 줄이다.
///
/// 프레임마다 `DetailPanelShareCard`를 그대로 렌더한다(§5.8). 정지 카드와 영상이 같은 뷰라
/// 레이아웃이 갈라질 수 없고, 마지막 프레임은 정지 카드와 같은 그림이 된다.
/// 경로선도 `RouteSnapshotRenderer.draw(progress:)` 한 곳에서 그린다.
@MainActor
enum RouteStampVideoExporter {

    static let fps            = 30
    static let minDrawSeconds = 8.0     // 짧은 러닝이 그려지는 시간
    static let maxDrawSeconds = 12.0    // 긴 러닝이 그려지는 시간
    static let holdSeconds    = 1.5     // 다 그린 뒤 머무는 시간

    /// 경로가 그려지는 시간 — 거리에 따라 8~12초.
    ///
    /// 길이를 고정하면 러닝이 길수록 화면이 빨리 흘러간다. 8초 고정이면 마라톤은 1초에 15분씩
    /// 지나가 숫자가 스쳐 간다. 5km까지는 8초, 30km에서 12초, 그 사이는 비례. 그 위는 12초에서 멈춘다.
    /// 상한을 12초로 둔 이유는 피드에서 더 길면 끝까지 보지 않기 때문이다.
    static func drawSeconds(distanceM: Double) -> Double {
        let km = distanceM / 1000
        let t = (km - 5) / 25
        return min(maxDrawSeconds, max(minDrawSeconds, minDrawSeconds + t * (maxDrawSeconds - minDrawSeconds)))
    }

    /// 인터벌은 회차 줄이 쌓이는 걸 읽어야 해서 더 천천히 — 기본 시간의 1.5배(최소 12초·최대 16초), 끝에 머무는 시간도 2.5초.
    /// 인터벌 여부는 운동 구간 2개 이상(회차 보드가 생기는 조건과 같다).
    static func isIntervalRun(_ detail: ActivityDetail?) -> Bool {
        (detail?.intervalSegments ?? []).filter { $0.stepLabel == "운동" }.count >= 2
    }
    static func drawSeconds(distanceM: Double, isInterval: Bool) -> Double {
        let base = drawSeconds(distanceM: distanceM)
        return isInterval ? min(16.0, max(12.0, base * 1.5)) : base
    }
    static func holdSeconds(isInterval: Bool) -> Double { isInterval ? 2.5 : holdSeconds }
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
        /// 멈춘 동안의 표본을 뺀 심박 — 시계 시간 오프셋 오름차순.
        private let hrSamples: [(offset: TimeInterval, bpm: Int)]
        /// 심박 존 경계 — 숫자 색을 고르는 데 쓴다. 비어 있으면 색을 주지 않는다.
        private let zoneBounds: [(id: Int, minBPM: Int)]
        /// 심박을 평균낼 앞뒤 초 — 러닝을 전체의 1%쯤으로 나눈 폭.
        /// 언덕에서 오르고 내리막에서 내려가는 모양은 남기면서 프레임 사이 잡음만 지운다.
        private let hrHalfWindow: TimeInterval

        /// `timeOffsets`는 시계 시간이라 워치에서 멈춘 동안도 흐른다. 실제 달린 시간으로 바꿔 함께 들고 있는다.
        /// 그래야 멈춰 있던 구간에서 시간과 페이스가 같이 멈추고, 끝 값도 총 시간과 맞는다.
        init(coordinates: [CLLocationCoordinate2D], timeOffsets: [TimeInterval],
             pausedSpans: [PausedSpan],
             hrSamples: [(offset: TimeInterval, bpm: Int)],
             zoneBounds: [(id: Int, minBPM: Int)],
             totalDistanceM: Double, totalDuration: TimeInterval) {
            self.zoneBounds     = zoneBounds
            self.totalDistanceM = totalDistanceM
            self.totalDuration  = totalDuration
            self.hrHalfWindow   = max(2.5, totalDuration / 120)
            if timeOffsets.count == coordinates.count {
                self.wallOffsets = timeOffsets
                self.offsets = timeOffsets.map { pausedSpans.activeElapsed(atWallOffset: $0) }
            } else {
                self.wallOffsets = []
                self.offsets = []
            }
            // 멈춘 동안의 심박은 쉬는 심박이라 달리는 중 값으로 보여주면 안 된다 — 빼고 쓴다
            self.hrSamples = hrSamples
                .filter { sample in !pausedSpans.contains { sample.offset >= $0.start && sample.offset < $0.end } }
                .sorted { $0.offset < $1.offset }
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
            let bpm = heartRate(at: p)
            return RouteProgressSnapshot(progress: p,
                                         distanceM: totalDistanceM * p,
                                         elapsed: elapsed(at: p),
                                         heartRate: bpm,
                                         heartRateColor: bpm.flatMap(zoneColor))
        }

        /// 심박 숫자의 색 — 지도 경로선을 칠하는 **같은 함수**를 쓴다(§5.8).
        /// 그래서 그 시점 경로선의 색과 숫자 색이 정확히 같다.
        private func zoneColor(_ bpm: Int) -> Color? {
            guard zoneBounds.count >= 2 else { return nil }
            return Color(RouteSnapshotRenderer.color(bpm: bpm, bounds: zoneBounds))
        }

        /// 그 시점의 심박. 상세 지도의 심박 존 색과 **같은 함수**를 쓰고 창 폭만 넓힌다(§5.8).
        /// 누적 평균이 아니라 순간값이라 오르막에서 오르고 내리막에서 내려간다.
        /// 표본이 없으면 칸을 만들지 않는다 — 순간값 자리에 러닝 전체 평균을 넣으면 뜻이 달라진다.
        private func heartRate(at p: Double) -> Int? {
            guard !hrSamples.isEmpty else { return nil }
            return RouteSnapshotRenderer.smoothedBPM(at: wallOffset(at: p),
                                                     samples: hrSamples,
                                                     halfWindow: hrHalfWindow).bpm
        }

        /// 진행률(거리)에 해당하는 좌표의 시계 시간. 심박 표본이 시계 시간이라 짝을 맞출 때 쓴다.
        private func wallOffset(at p: Double) -> TimeInterval {
            interpolate(wallOffsets, at: p) ?? (hrSamples.last?.offset ?? 0) * p
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

    /// 좌표를 거르고 진행표를 만든다 — 내보내기와 미리보기가 **같은 값**을 쓰도록 여기 한 곳에서만 만든다.
    /// 좌표와 시간 오프셋을 같은 판정으로 함께 걸러야 인덱스가 어긋나지 않는다.
    private static func prepare(
        activity: Activity,
        detail: ActivityDetail?,
        hrSamples: [(offset: TimeInterval, bpm: Int)]
    ) -> (coords: [CLLocationCoordinate2D], table: ProgressTable)? {
        let rawCoords  = detail?.routeCoordinates ?? []
        let rawOffsets = detail?.routeTimeOffsets ?? []
        let keep = rawCoords.indices.filter { RouteSnapshotRenderer.isValid(rawCoords[$0]) }
        let coords  = keep.map { rawCoords[$0] }
        let offsets = rawOffsets.count == rawCoords.count ? keep.map { rawOffsets[$0] } : []
        guard coords.count > 1 else { return nil }
        let table = ProgressTable(coordinates: coords, timeOffsets: offsets,
                                  pausedSpans: detail?.pausedSpans ?? [],
                                  hrSamples: hrSamples,
                                  zoneBounds: RouteSnapshotRenderer.zoneBounds(
                                      zones: detail?.hrZones ?? [], hrSamples: hrSamples),
                                  totalDistanceM: activity.distance,
                                  totalDuration: activity.duration)
        return (coords, table)
    }

    /// 영상의 **마지막 프레임 값**. 영상 모드 미리보기가 이 값으로 정지 화면을 그려
    /// 화면에서 보는 것과 내보낸 영상의 끝이 같아진다(거리·페이스·시간·심박 네 칸).
    static func finalSnapshot(
        activity: Activity,
        detail: ActivityDetail?,
        hrSamples: [(offset: TimeInterval, bpm: Int)]
    ) -> RouteProgressSnapshot? {
        prepare(activity: activity, detail: detail, hrSamples: hrSamples)?.table.snapshot(at: 1)
    }

    // MARK: - 내보내기

    static func export(
        activity: Activity,
        detail: ActivityDetail?,
        condition: ActivityCondition?,
        age: Int?,
        isMale: Bool?,
        placeName: String?,
        /// 확정된 대회 이름 — 정지 카드와 같은 자리(맨 윗줄 오른쪽)에 프레임마다 그린다.
        raceName: String? = nil,
        segmentColors: [UIColor]?,
        /// 시점별 심박 — 시계 시간 오프셋. 그 시점의 심박을 읽는 데 쓴다.
        hrSamples: [(offset: TimeInterval, bpm: Int)],
        onProgress: @escaping (Double) -> Void
    ) async throws -> URL {

        guard let (coords, table) = prepare(activity: activity, detail: detail, hrSamples: hrSamples) else {
            throw ExportError.noRoute
        }

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

        let interval    = isIntervalRun(detail)
        let animFrames  = Int(drawSeconds(distanceM: activity.distance, isInterval: interval) * Double(fps))
        let holdFrames  = Int(holdSeconds(isInterval: interval) * Double(fps))
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
                    routeProgress: table.snapshot(at: p),
                    raceName: raceName
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

/// 경로 1의 결과물 — 정지 이미지 / 영상.
enum StampOutputMode { case image, video }
