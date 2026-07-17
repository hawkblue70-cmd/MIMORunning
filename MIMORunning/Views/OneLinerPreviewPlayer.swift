import AVFoundation
import Observation
import SwiftUI
import UIKit
import CoreLocation

// MARK: - OneLinerPreviewPlayer
//
// Owns one AVPlayer + AVSynchronizedLayer session for live card preview.
// Use buildForPhotoSlides or buildForVideoClips; invalidate() tears everything down.

@Observable
@MainActor
final class OneLinerPreviewPlayer {
    var isBuilding: Bool   = false
    var isPlaying:  Bool   = false
    var progress:   Double = 0
    var isReady:    Bool   = false

    private(set) var player:       AVPlayer?
    private(set) var contentLayer: CALayer?
    private(set) var renderSize:   CGSize = .zero
    private(set) var duration:     Double = 0

    private var tempURL: URL?
    private var timeObserver: Any?
    private var endObserver:  NSObjectProtocol?

    // MARK: Build

    func buildForPhotoSlides(
        photos:           [UIImage],
        recipes:          [ClipRecipe],
        activityDate:     Date,
        showDate:         Bool,
        metricChips:      [VideoMetricChip] = [],
        metricLookup:     [String: VideoMetricChip] = [:],
        routeCoords:      [CLLocationCoordinate2D] = [],
        hrSamples:        [(offset: TimeInterval, bpm: Int)] = [],
        splits:           [SplitData] = [],
        chartSeriesData:  [ChartOverlayType: [(offset: TimeInterval, value: Double)]] = [:],
        hrZones:          [HRZoneData] = [],
        intervalSegments: [IntervalSegment] = [],
        videoTitle:       String            = "",
        titleStyle:       OneLinerTitleStyle = OneLinerTitleStyle(),
        dataOverlayImage: UIImage?           = nil
    ) async {
        invalidate()
        isBuilding = true
        defer { isBuilding = false }
        do {
            let result = try await PhotoSlideComposition.buildPreviewItem(
                photos:           photos,
                recipes:          recipes,
                activityDate:     activityDate,
                showDate:         showDate,
                metricChips:      metricChips,
                metricLookup:     metricLookup,
                routeCoords:      routeCoords,
                hrSamples:        hrSamples,
                splits:           splits,
                chartSeriesData:  chartSeriesData,
                hrZones:          hrZones,
                intervalSegments: intervalSegments,
                videoTitle:       videoTitle,
                titleStyle:       titleStyle,
                dataOverlayImage: dataOverlayImage)
            setUpPlayer(playerItem: result.playerItem, animLayer: result.layer,
                        renderSize: result.size, duration: result.duration)
            tempURL = result.tempURL
        } catch {
            print("[OneLinerPreview] Photo slide build failed: \(error)")
        }
    }

    func buildForVideoClips(
        recipes:          [ClipRecipe],
        activityDate:     Date,
        showDate:         Bool,
        muteAudio:        Bool = false,
        metricChips:      [VideoMetricChip] = [],
        metricLookup:     [String: VideoMetricChip] = [:],
        routeCoords:      [CLLocationCoordinate2D] = [],
        hrSamples:        [(offset: TimeInterval, bpm: Int)] = [],
        splits:           [SplitData] = [],
        chartSeriesData:  [ChartOverlayType: [(offset: TimeInterval, value: Double)]] = [:],
        hrZones:          [HRZoneData] = [],
        intervalSegments: [IntervalSegment] = [],
        videoTitle:       String            = "",
        titleStyle:       OneLinerTitleStyle = OneLinerTitleStyle()
    ) async {
        invalidate()
        isBuilding = true
        defer { isBuilding = false }
        do {
            let result = try await VideoExportService.buildVideoPreviewItem(
                recipes:          recipes,
                activityDate:     activityDate,
                showDate:         showDate,
                muteAudio:        muteAudio,
                metricChips:      metricChips,
                metricLookup:     metricLookup,
                routeCoords:      routeCoords,
                hrSamples:        hrSamples,
                splits:           splits,
                hrZones:          hrZones,
                intervalSegments: intervalSegments,
                chartSeriesData:  chartSeriesData,
                videoTitle:       videoTitle,
                titleStyle:       titleStyle)
            setUpPlayer(playerItem: result.playerItem, animLayer: result.layer,
                        renderSize: result.size, duration: result.duration)
            player?.isMuted = muteAudio
        } catch {
            print("[OneLinerPreview] Video clip build failed: \(error)")
        }
    }

    // MARK: Mute — apply instantly without rebuild
    func setMuted(_ muted: Bool) {
        player?.isMuted = muted
    }

    // MARK: Playback control

    func togglePlayPause() { isPlaying ? pause() : play() }

    func play() {
        guard let player else { return }
        if progress >= 1.0 { player.seek(to: .zero) }
        player.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func invalidate() {
        if let obs = timeObserver { player?.removeTimeObserver(obs) }
        timeObserver = nil
        if let obs = endObserver { NotificationCenter.default.removeObserver(obs) }
        endObserver  = nil
        player?.pause()
        player       = nil
        contentLayer = nil
        renderSize   = .zero
        duration     = 0
        isReady      = false
        isPlaying    = false
        progress     = 0
        if let url = tempURL { try? FileManager.default.removeItem(at: url) }
        tempURL = nil
    }


    // MARK: Private

    private func setUpPlayer(
        playerItem: AVPlayerItem,
        animLayer:  CALayer,
        renderSize: CGSize,
        duration:   Double
    ) {
        let avPlayer = AVPlayer(playerItem: playerItem)
        let interval = CMTimeMake(value: 1, timescale: 30)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, self.duration > 0 else { return }
                self.progress = min(CMTimeGetSeconds(time) / self.duration, 1.0)
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object:  playerItem,
            queue:   .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isPlaying = false
                self?.progress  = 1.0
            }
        }
        self.player       = avPlayer
        self.contentLayer = animLayer
        self.renderSize   = renderSize
        self.duration     = duration
        self.isReady      = true
    }
}

// MARK: - OneLinerPreviewView

struct OneLinerPreviewView: UIViewRepresentable {
    let player:       AVPlayer
    let contentLayer: CALayer
    let renderSize:   CGSize

    func makeUIView(context: Context) -> PreviewHostView {
        let view = PreviewHostView()
        view.configure(player: player, contentLayer: contentLayer, renderSize: renderSize)
        return view
    }

    func updateUIView(_ uiView: PreviewHostView, context: Context) {
        uiView.configure(player: player, contentLayer: contentLayer, renderSize: renderSize)
    }
}

// MARK: - PreviewHostView
//
// UIView whose backing layer is AVPlayerLayer.
// Adds an AVSynchronizedLayer on top; the content layer (text / photo animations)
// lives inside the synchronized layer and is scaled to fit the view.

final class PreviewHostView: UIView {
    private var syncLayer:    AVSynchronizedLayer?
    private var contentLayer: CALayer?
    private var renderSize:   CGSize = .zero

    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var avPlayerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    func configure(player: AVPlayer, contentLayer: CALayer, renderSize: CGSize) {
        self.renderSize   = renderSize
        self.contentLayer = contentLayer

        // 이전 syncLayer 제거 — updateUIView로 재호출 시 누적 방지
        syncLayer?.removeFromSuperlayer()
        syncLayer = nil

        avPlayerLayer.player       = player
        avPlayerLayer.videoGravity = .resizeAspectFill

        guard let item = player.currentItem else { return }
        let sync = AVSynchronizedLayer(playerItem: item)
        sync.frame = bounds
        layer.addSublayer(sync)
        syncLayer = sync

        applyContentScale()
        sync.addSublayer(contentLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        syncLayer?.frame = bounds
        applyContentScale()
    }

    private func applyContentScale() {
        guard let cl = contentLayer, renderSize.width > 0, !bounds.isEmpty else { return }
        let scale = min(bounds.width / renderSize.width, bounds.height / renderSize.height)
        cl.bounds      = CGRect(origin: .zero, size: renderSize)
        cl.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        cl.position    = CGPoint(x: bounds.midX, y: bounds.midY)
        cl.transform   = CATransform3DMakeScale(scale, scale, 1)
    }
}

// MARK: - RawVideoPlayerView

/// Raw AVPlayer display — no overlay compositing. Used for Placeable card video background preview.
struct RawVideoPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> RawPlayerUIView { RawPlayerUIView() }
    func updateUIView(_ uiView: RawPlayerUIView, context: Context) { uiView.player = player }

    final class RawPlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        private var avLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var player: AVPlayer? {
            get { avLayer.player }
            set { avLayer.player = newValue; avLayer.videoGravity = .resizeAspectFill }
        }
        override func layoutSubviews() { super.layoutSubviews(); avLayer.frame = bounds }
    }
}

// MARK: - PlaceableVideoState

/// Lightweight video state for Placeable card video background preview.
@Observable
@MainActor
final class PlaceableVideoState {
    var isPlaying:   Bool   = false
    var progress:    Double = 0
    var isReady:     Bool   = false
    /// 현재 재생 위치(초). 멀티 클립 미리보기에서 어느 클립이 재생 중인지 판단에 사용.
    var currentTime: Double = 0

    private(set) var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver:  NSObjectProtocol?

    func load(url: URL) {
        invalidate()
        let p = AVPlayer(url: url)
        p.isMuted = true
        setupObservers(player: p, playerItem: p.currentItem, knownDuration: nil)
        player  = p
        isReady = true
    }

    /// 이미 구성된 AVPlayerItem(예: 멀티클립 합성 미리보기)을 직접 로드.
    func loadPlayerItem(_ item: AVPlayerItem, duration: Double) {
        invalidate()
        let p = AVPlayer(playerItem: item)
        p.isMuted = true
        setupObservers(player: p, playerItem: item, knownDuration: duration)
        player  = p
        isReady = true
    }

    private func setupObservers(player p: AVPlayer, playerItem: AVPlayerItem?, knownDuration: Double?) {
        let iv = CMTimeMake(value: 1, timescale: 30)
        timeObserver = p.addPeriodicTimeObserver(forInterval: iv, queue: .main) { [weak self, weak p] t in
            Task { @MainActor [weak self, weak p] in
                guard let self else { return }
                let dur: Double
                if let kd = knownDuration {
                    dur = kd
                } else if let item = p?.currentItem {
                    let d = item.duration.seconds
                    guard d.isFinite, d > 0 else { return }
                    dur = d
                } else { return }
                self.currentTime = t.seconds
                self.progress = min(t.seconds / dur, 1.0)
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isPlaying = false
                self?.progress  = 1.0
            }
        }
    }

    func togglePlayPause() {
        guard let p = player else { return }
        if isPlaying { p.pause(); isPlaying = false }
        else {
            if progress >= 1.0 { p.seek(to: .zero) }
            p.play(); isPlaying = true
        }
    }

    func pause() { player?.pause(); isPlaying = false }

    func invalidate() {
        if let obs = timeObserver { player?.removeTimeObserver(obs) }
        if let obs = endObserver  { NotificationCenter.default.removeObserver(obs) }
        player?.pause()
        player = nil; timeObserver = nil; endObserver = nil
        isPlaying = false; progress = 0; currentTime = 0; isReady = false
    }
}
