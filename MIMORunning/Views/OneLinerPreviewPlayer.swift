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
    // 어느 카드가 이 player를 빌드했는지 추적 (nil=없음)
    // 같은 카드로 복귀 시 불필요한 재빌드를 생략하는 데 사용
    var builtForCard: ShareCard? = nil
    // 슬라이드(사진) 빌드였으면 true, 영상 클립 빌드였으면 false
    // OneLiner 재진입 시 player 컨텐츠가 현재 template과 불일치하면 invalidate하기 위해 사용
    var builtForPhotoSlide: Bool = false
    // player가 교체될 때마다 갱신 — stampSlidePreviewSection의 OneLinerPreviewView에
    // .id(buildToken)을 걸어 UIView 재생성 → onAppear 재발동 → seek 보장
    private(set) var buildToken: UUID = UUID()

    private(set) var player:       AVPlayer?
    private(set) var contentLayer: CALayer?
    private(set) var renderSize:   CGSize = .zero
    private(set) var duration:     Double = 0

    private var tempURL: URL?
    private var timeObserver: Any?
    private var endObserver:  NSObjectProtocol?
    // 빌드 중 setMuted 호출이 발생해도 완료 시 반영되도록 원하는 상태를 별도 추적
    private var targetMuted: Bool = false
    // 빌드 세대 카운터 — invalidate() 마다 증가, 이전 빌드가 setUpPlayer를 덮어쓰는 race 방지
    private var buildGeneration: Int = 0

    // MARK: Build

    func buildForPhotoSlides(
        photos:           [UIImage],
        recipes:          [ClipRecipe],
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
        dataOverlayImage: UIImage?           = nil,
        dataOverlayIsTop: Bool               = false,
        fastBase:         Bool               = false,
        forCard:          ShareCard?        = nil
    ) async {
        invalidate()                         // buildGeneration 증가 → 이전 빌드 무효화
        buildGeneration += 1
        let myGen = buildGeneration
        isBuilding = true
        defer { isBuilding = false }
        do {
            let result = try await PhotoSlideComposition.buildPreviewItem(
                photos:           photos,
                recipes:          recipes,
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
                dataOverlayImage: dataOverlayImage,
                dataOverlayIsTop: dataOverlayIsTop,
                fastBase:         fastBase)
            guard buildGeneration == myGen else { return }  // 대기 중 invalidate 됐으면 폐기
            setUpPlayer(playerItem: result.playerItem, animLayer: result.layer,
                        renderSize: result.size, duration: result.duration)
            builtForCard = forCard
            builtForPhotoSlide = true
            tempURL = result.tempURL
        } catch {
        }
    }

    func buildForVideoClips(
        recipes:          [ClipRecipe],
        showWordmark:     Bool = true,
        muteAudio:        Bool = false,  // 빌드 시작 시 초기 상태; 빌드 중 setMuted 호출이 있으면 그 값이 우선
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
        safeTopOverride:  CGFloat?           = nil,
        safeBotOverride:  CGFloat?           = nil,
        wordmarkTopPad:   CGFloat?           = nil,
        dataOverlayImage: UIImage?           = nil,
        fullSizeOverlayImage: UIImage?       = nil,
        forCard:          ShareCard?        = nil
    ) async {
        targetMuted = muteAudio   // 초기 상태 기록; 빌드 중 setMuted 호출로 덮어쓸 수 있음
        invalidate()                         // buildGeneration 증가 → 이전 빌드 무효화
        buildGeneration += 1
        let myGen = buildGeneration
        isBuilding = true
        defer { isBuilding = false }
        do {
            let result = try await VideoExportService.buildVideoPreviewItem(
                recipes:          recipes,
                showWordmark:     showWordmark,
                muteAudio:        false,   // 프리뷰는 항상 오디오 트랙 포함; 음소거는 player.isMuted로 제어
                metricChips:      metricChips,
                metricLookup:     metricLookup,
                routeCoords:      routeCoords,
                hrSamples:        hrSamples,
                splits:           splits,
                hrZones:          hrZones,
                intervalSegments: intervalSegments,
                chartSeriesData:  chartSeriesData,
                videoTitle:       videoTitle,
                titleStyle:       titleStyle,
                safeTopOverride:      safeTopOverride,
                safeBotOverride:      safeBotOverride,
                wordmarkTopPad:       wordmarkTopPad,
                dataOverlayImage:     dataOverlayImage,
                fullSizeOverlayImage: fullSizeOverlayImage)
            guard buildGeneration == myGen else { return }  // 대기 중 invalidate 됐으면 폐기
            setUpPlayer(playerItem: result.playerItem, animLayer: result.layer,
                        renderSize: result.size, duration: result.duration)
            builtForCard = forCard
            builtForPhotoSlide = false
            player?.isMuted = targetMuted   // 캡처된 muteAudio 대신 현재 상태 적용
        } catch {
        }
    }

    /// 이미 완성된 영상 URL을 플레이어에 로드한다.
    /// exportStampSlide 등 외부에서 렌더된 파일을 로드할 때 사용.
    /// 호출 전 invalidate() 불필요 — 내부에서 정리 후 로드.
    func loadPrebuiltURL(_ url: URL, videoSize: CGSize = CGSize(width: 1080, height: 1920)) async {
        invalidate()
        isBuilding = true
        defer { isBuilding = false }
        do {
            let asset = AVURLAsset(url: url)
            let dur   = try await asset.load(.duration)
            let item  = AVPlayerItem(asset: asset)
            setUpPlayer(playerItem: item, animLayer: CALayer(),
                        renderSize: videoSize, duration: CMTimeGetSeconds(dur))
            tempURL = url
        } catch {
        }
    }

    // MARK: Mute — apply instantly without rebuild
    func setMuted(_ muted: Bool) {
        targetMuted = muted   // 빌드 중이더라도 완료 시 반영됨
        player?.isMuted = muted
    }

    // MARK: Playback control

    func togglePlayPause() { isPlaying ? pause() : play() }

    func play() {
        guard let player else { return }
        isPlaying = true   // UI 즉시 업데이트 (버튼 → 일시정지 표시)
        if progress >= 0.95 {
            // 끝이거나 거의 끝(95%+) → 처음부터 재시작.
            // seek 이전에 play() 호출하면 끝 위치부터 재생 → endObserver 즉시 발동
            // → isPlaying = false 루프에 빠져 재생 불가 상태가 됨.
            player.seek(to: .zero) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.player?.play()
                }
            }
        } else {
            player.play()
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func invalidate() {
        buildGeneration += 1  // 진행 중인 빌드의 guard 체크를 무효화
        // isReady/isPlaying을 먼저 false로: SwiftUI observation이 player=nil 보다 앞서
        // 뷰를 다시 그리더라도 player를 사용하는 분기에 진입하지 않도록 보장
        isReady           = false
        isPlaying         = false
        builtForCard = nil
        builtForPhotoSlide = false
        if let obs = timeObserver { player?.removeTimeObserver(obs) }
        timeObserver = nil
        if let obs = endObserver { NotificationCenter.default.removeObserver(obs) }
        endObserver  = nil
        player?.pause()
        // AVPlayer dealloc과 파일 삭제를 백그라운드에서 처리 — 메인 스레드 블로킹 방지
        let oldPlayer = player
        let oldURL    = tempURL
        player       = nil
        contentLayer = nil
        renderSize   = .zero
        duration     = 0
        progress     = 0
        tempURL = nil
        Task.detached {
            _ = oldPlayer  // 백그라운드에서 dealloc
            if let url = oldURL { try? FileManager.default.removeItem(at: url) }
        }
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
        self.buildToken   = UUID()
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
        self.renderSize = renderSize
        avPlayerLayer.player       = player
        avPlayerLayer.videoGravity = .resizeAspectFill

        guard let item = player.currentItem else {
            syncLayer?.removeFromSuperlayer()
            syncLayer = nil
            self.contentLayer = nil
            return
        }

        // playerItem이 바뀔 때만 syncLayer 재생성 — progress 변경으로 updateUIView가
        // 매 프레임 호출되어도 AVSynchronizedLayer를 재생성하지 않음 → 애니메이션 리셋 방지
        if syncLayer?.playerItem !== item {
            syncLayer?.removeFromSuperlayer()
            let sync = AVSynchronizedLayer(playerItem: item)
            sync.frame = bounds
            layer.addSublayer(sync)
            syncLayer = sync
            applyContentScale()
        }

        // contentLayer가 교체됐을 때만 재연결
        if self.contentLayer !== contentLayer {
            self.contentLayer?.removeFromSuperlayer()
            self.contentLayer = contentLayer
            syncLayer?.addSublayer(contentLayer)
            applyContentScale()
        }
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

// MARK: - SyncLayerView
//
// 투명 UIView + AVSynchronizedLayer. AVPlayerLayer 없이 contentLayer(Ken Burns 등)만 렌더.
// AVPlayerLayer(검은 배경)을 쓰지 않으므로, 뒤의 SwiftUI 배경 사진이 그대로 비침.
// 슬라이드 미리보기에서 검은 화면 없이 Ken Burns 애니메이션을 표시할 때 사용.

struct SyncLayerView: UIViewRepresentable {
    let playerItem:   AVPlayerItem
    let contentLayer: CALayer
    let renderSize:   CGSize

    func makeUIView(context: Context) -> SyncHostView {
        let view = SyncHostView()
        view.configure(playerItem: playerItem, contentLayer: contentLayer, renderSize: renderSize)
        return view
    }

    func updateUIView(_ uiView: SyncHostView, context: Context) {
        uiView.configure(playerItem: playerItem, contentLayer: contentLayer, renderSize: renderSize)
    }
}

final class SyncHostView: UIView {
    private var syncLayer:    AVSynchronizedLayer?
    private var contentLayer: CALayer?
    private var renderSize:   CGSize = .zero

    func configure(playerItem: AVPlayerItem, contentLayer: CALayer, renderSize: CGSize) {
        self.renderSize = renderSize

        if syncLayer?.playerItem !== playerItem {
            syncLayer?.removeFromSuperlayer()
            let sync = AVSynchronizedLayer(playerItem: playerItem)
            sync.frame = bounds
            layer.addSublayer(sync)
            syncLayer = sync
            applyContentScale()
        }

        if self.contentLayer !== contentLayer {
            self.contentLayer?.removeFromSuperlayer()
            self.contentLayer = contentLayer
            syncLayer?.addSublayer(contentLayer)
            applyContentScale()
        }
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
        p.isMuted = false
        setupObservers(player: p, playerItem: p.currentItem, knownDuration: nil)
        player  = p
        isReady = true
    }

    /// 이미 구성된 AVPlayerItem(예: 멀티클립 합성 미리보기)을 직접 로드.
    func loadPlayerItem(_ item: AVPlayerItem, duration: Double) {
        invalidate()
        let p = AVPlayer(playerItem: item)
        p.isMuted = false
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
