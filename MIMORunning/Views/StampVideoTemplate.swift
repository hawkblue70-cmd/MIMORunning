// 스탬프 카드 — 영상 미리보기·합성 출력.
// 러닝 데이터는 영상 내내 고정이므로, StampCard 를 이미지로 1회 렌더해
// CALayer 오버레이로 얹는다(프레임마다 다시 그리지 않음).
// ⚠️ 스탬프 카드 전용.

import SwiftUI
import AVFoundation

// MARK: - StampCard → UIImage (1080×1920 px 기준)

@MainActor
func makeStampOverlayImage(data: StampData, vm: StampViewModel,
                           isBright: Bool, renderSize: CGSize,
                           configOverride: StampPhotoConfig? = nil,
                           renderOnlyStamp: Bool = false,
                           renderOnlyText: Bool = false) -> UIImage? {
    // 9:16 캔버스를 300pt 폭으로 고정, 높이는 비례 계산
    let ptH = renderSize.height / renderSize.width * 300
    let cfg = configOverride ?? vm.currentConfig
    let card = StampCard(
        data: data,
        template: cfg.template,
        colorMode: cfg.colorMode,
        position: cfg.position,
        sizeLevel: cfg.sizeLevel,
        isBrightBackground: isBright,
        showHeartRate: cfg.showHeartRate,
        showCalories: cfg.showCalories,
        showTextOutline: cfg.showTextOutline,
        stampText: cfg.text,
        stampTextPosition: cfg.textPosition,
        stampTextFont: cfg.textFont,
        stampTextSize: cfg.textSize,
        stampTextColor: cfg.textColor,
        stampTextHasBorder: cfg.textHasBorder,
        renderOnlyStamp: renderOnlyStamp,
        renderOnlyText: renderOnlyText
    )
    // 위아래 6% 여백: 88% 높이로 렌더 후 전체 높이로 감쌈 → 자동으로 6% top/bottom 마진
    .frame(width: 300, height: ptH * 0.88)
    .frame(width: 300, height: ptH)
    let renderer = ImageRenderer(content: card)
    renderer.proposedSize = .init(width: 300, height: ptH)
    renderer.scale = renderSize.width / 300  // 3.6 for 1080-wide video → 1080×1920 px
    renderer.isOpaque = false
    _ = renderer.uiImage   // 첫 호출은 SwiftUI 파이프라인 미초기화로 잘못된 이미지를 반환할 수 있음 — 버림
    return renderer.uiImage
}

// MARK: - 워드마크·날짜 오버레이 이미지 (슬라이드 출력용 정적 레이어)

/// 슬라이드 출력에 얹히는 MIMO 워드마크(좌) + 날짜(우) 정적 이미지.
/// 9:16 캔버스(renderSize) 기준으로 렌더 → scale 적용으로 px 출력.
@MainActor
func makeStampLogoDateOverlay(date: Date, renderSize: CGSize) -> UIImage? {
    let ptH = renderSize.height / renderSize.width * 300
    let vPad = ptH * 0.06
    let df = DateFormatter(); df.dateFormat = "yyyy.MM.dd"
    let dateStr = df.string(from: date)

    let overlay = HStack(alignment: .firstTextBaseline, spacing: 0) {
        Text("MIMO")
            .font(.system(size: 9, weight: .black))
            .tracking(2)
            .foregroundStyle(.white)
        Text(" RUNNING")
            .font(.system(size: 9, weight: .bold))
            .tracking(2)
            .foregroundStyle(Theme.violet)
        Spacer()
        Text(dateStr)
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(.white)
    }
    .cardTextShadow()
    .padding(.leading, 14)
    .padding(.trailing, 14)
    .padding(.top, vPad)
    .frame(width: 300, height: ptH, alignment: .top)

    let renderer = ImageRenderer(content: overlay)
    renderer.proposedSize = .init(width: 300, height: ptH)
    renderer.scale = renderSize.width / 300
    renderer.isOpaque = false
    return renderer.uiImage
}

/// 영상 출력에 얹히는 MIMO 워드마크(좌) + 날짜(우) 정적 이미지.
@MainActor
func makeStampLogoOverlay(date: Date, renderSize: CGSize) -> UIImage? {
    let ptH  = renderSize.height / renderSize.width * 300
    let vPad = ptH * 0.06
    let df = DateFormatter(); df.dateFormat = "yyyy.MM.dd"
    let dateStr = df.string(from: date)
    let overlay = HStack(alignment: .firstTextBaseline, spacing: 0) {
        Text("MIMO")
            .font(.system(size: 9, weight: .black))
            .tracking(2)
            .foregroundStyle(.white)
        Text(" RUNNING")
            .font(.system(size: 9, weight: .bold))
            .tracking(2)
            .foregroundStyle(Theme.violet)
        Spacer()
        Text(dateStr)
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(.white)
    }
    .cardTextShadow()
    .padding(.leading, 14)
    .padding(.trailing, 14)
    .padding(.top, vPad)
    .frame(width: 300, height: ptH, alignment: .topLeading)
    let renderer = ImageRenderer(content: overlay)
    renderer.proposedSize = .init(width: 300, height: ptH)
    renderer.scale = renderSize.width / 300
    renderer.isOpaque = false
    return renderer.uiImage
}

// MARK: - 밝기 판정

func stampVideoIsBright(vm: StampViewModel) -> Bool {
    stampBackgroundIsBright(photo: vm.clipRecipes.first?.thumbnail, position: vm.position)
}

// MARK: - 스탬프 영상 썸네일 (비디오 프레임 + 스탬프 오버레이 합성)

/// 첫 번째 클립 썸네일에 스탬프 오버레이를 얹어 공유용 정적 이미지를 만든다.
/// 출력 크기: 1080×1920 px (9:16)
@MainActor
func makeStampVideoThumbnail(data: StampData, vm: StampViewModel) -> UIImage? {
    let outSize = CGSize(width: 1080, height: 1920)

    // 배경: 첫 클립 썸네일. 없으면 어두운 단색으로 대체.
    let bgImage = vm.clipRecipes.first?.thumbnail

    // 스탬프 오버레이 (투명 배경)
    let isBright = stampVideoIsBright(vm: vm)
    guard let overlay = makeStampOverlayImage(
        data: data, vm: vm,
        isBright: isBright, renderSize: outSize)
    else { return nil }

    let format = UIGraphicsImageRendererFormat()
    format.scale = 1.0
    let renderer = UIGraphicsImageRenderer(size: outSize, format: format)
    return renderer.image { ctx in
        if let bg = bgImage {
            // scale-fill: 비율 유지하며 꽉 채우기
            let s = max(outSize.width / bg.size.width, outSize.height / bg.size.height)
            let dw = bg.size.width * s
            let dh = bg.size.height * s
            let ox = (outSize.width  - dw) / 2
            let oy = (outSize.height - dh) / 2
            bg.draw(in: CGRect(x: ox, y: oy, width: dw, height: dh))
        } else {
            UIColor(red: 0.14, green: 0.16, blue: 0.15, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: outSize))
        }
        overlay.draw(in: CGRect(origin: .zero, size: outSize))
    }
}

// MARK: - CALayer 빌더 (전체 프레임 덮는 투명 레이어)

func buildStampOverlayLayer(
    from image: UIImage,
    renderSize: CGSize,
    mode: StampEntranceMode,
    flyDirection: FlyInDirection = .trailing,
    beginTimeOffset: Double = 0.0
) -> CALayer {
    let layer = CALayer()
    layer.frame = CGRect(origin: .zero, size: renderSize)
    layer.contents = image.cgImage
    layer.contentsGravity = .resize
    layer.contentsScale = 1.0

    func makeAnim(_ keyPath: String, keyTimes: [NSNumber], values: [Any],
                  duration: Double) -> CAKeyframeAnimation {
        let a = CAKeyframeAnimation(keyPath: keyPath)
        a.beginTime             = AVCoreAnimationBeginTimeAtZero + beginTimeOffset
        a.duration              = duration
        a.calculationMode       = .linear
        a.fillMode              = .both
        a.isRemovedOnCompletion = false
        a.keyTimes              = keyTimes
        a.values                = values
        return a
    }

    switch mode {

    case .none:
        break   // 정적 오버레이 — 애니메이션 없음

    case .stamp:
        // 도장 찍히는 등장 — onset 0.15s 대기 후 0.45s 입장
        let onset: Double = 0.15
        let dur:   Double = 0.45
        let total          = onset + dur
        func kT(_ v: Double) -> NSNumber { NSNumber(value: v / total) }

        let sc              = CAKeyframeAnimation(keyPath: "transform.scale")
        sc.values           = [0.01, 1.6, 0.92, 1.04, 1.0] as [NSNumber]
        sc.keyTimes         = [0, kT(onset), kT(onset + dur * 0.40),
                               kT(onset + dur * 0.70), 1.0]
        sc.calculationMode  = .linear

        let op             = CAKeyframeAnimation(keyPath: "opacity")
        op.values          = [0.0, 0.0, 1.0, 1.0, 1.0] as [NSNumber]
        op.keyTimes        = [0, kT(onset), kT(onset + dur * 0.30),
                              kT(onset + dur * 0.50), 1.0]
        op.calculationMode = .linear

        let rot             = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        let rad: Double     = -4.0 * .pi / 180.0
        rot.values          = [0.0, rad, 0.0, 0.0, 0.0] as [NSNumber]
        rot.keyTimes        = [0, kT(onset), kT(onset + dur * 0.70),
                               kT(onset + dur * 0.90), 1.0]
        rot.calculationMode = .linear

        let grp                    = CAAnimationGroup()
        grp.animations             = [sc, op, rot]
        grp.beginTime              = AVCoreAnimationBeginTimeAtZero + beginTimeOffset
        grp.duration               = total
        grp.fillMode               = .both
        grp.isRemovedOnCompletion  = false
        layer.add(grp, forKey: "stampEntrance")

    case .fade:
        let totalF: Double = 0.6
        layer.add(makeAnim("opacity",
                           keyTimes: [0, NSNumber(value: 0.15 / totalF),
                                      NSNumber(value: 0.55 / totalF), 1.0],
                           values: [0.0, 0.0, 1.0, 1.0] as [NSNumber],
                           duration: totalF), forKey: "stampFade")

    case .flyIn:
        let totalF: Double = 0.6
        let w = renderSize.width; let h = renderSize.height
        let key: String
        let startOffset: Double
        switch flyDirection {
        case .leading:  key = "transform.translation.x"; startOffset = -Double(w)
        case .trailing: key = "transform.translation.x"; startOffset =  Double(w)
        case .bottom:   key = "transform.translation.y"; startOffset =  Double(h)
        }
        // slide in with slight overshoot
        layer.add(makeAnim(key,
                           keyTimes: [0, NSNumber(value: 0.10 / totalF),
                                      NSNumber(value: 0.52 / totalF),
                                      NSNumber(value: 0.60 / totalF), 1.0],
                           values: [NSNumber(value: startOffset),
                                    NSNumber(value: startOffset),
                                    NSNumber(value: startOffset * -0.06),
                                    0.0, 0.0] as [NSNumber],
                           duration: totalF), forKey: "stampFlyTrans")
        layer.add(makeAnim("opacity",
                           keyTimes: [0, NSNumber(value: 0.10 / totalF),
                                      NSNumber(value: 0.30 / totalF), 1.0],
                           values: [0.0, 0.0, 1.0, 1.0] as [NSNumber],
                           duration: totalF), forKey: "stampFlyOp")
    }

    return layer
}

// MARK: - AnimatedStampPreviewCard

/// 영상 미리보기 전용 — 스탬프 레이어와 문구 레이어를 독립적으로 애니메이트.
/// 각 레이어는 AnimatedStampLayer 가 개별 .task(id:) 로 진입 애니메이션을 관리.
struct AnimatedStampPreviewCard: View {
    let data:     StampData
    @Bindable var vm: StampViewModel
    /// 슬라이드 재생 시 현재 장(playingIdx)의 config를 주입 — nil이면 vm.currentConfig 사용.
    var configOverride: StampPhotoConfig? = nil
    let isBright: Bool
    /// 슬라이드 장 인덱스 — 장이 바뀌면 AnimatedStampLayer의 animKey가 변경돼 애니메이션이 재시작됨
    var currentPhotoIndex: Int    = 0
    var previewProgress: Double = 0
    var isVideoPlaying:  Bool   = false

    var body: some View {
        let cfg = configOverride ?? vm.currentConfig
        let stampDur: Double = cfg.entranceMode == .none ? 0 : 0.60
        ZStack {
            // 스탬프 레이어 (문구 없이 스탬프만)
            AnimatedStampLayer(
                data: data, vm: vm, isBright: isBright,
                entranceMode: cfg.entranceMode,
                flyDirection: cfg.flyDirection,
                configOverride: configOverride,
                renderOnlyStamp: true,
                previewProgress: previewProgress,
                isVideoPlaying: isVideoPlaying,
                photoIndex: currentPhotoIndex
            )
            // 문구 레이어 (현재 장 텍스트가 있는 경우만) — 스탬프 완료 후 등장
            if !cfg.text.isEmpty {
                AnimatedStampLayer(
                    data: data, vm: vm, isBright: isBright,
                    entranceMode: cfg.textEntranceMode,
                    flyDirection: cfg.textFlyDirection,
                    configOverride: configOverride,
                    renderOnlyText: true,
                    previewProgress: previewProgress,
                    isVideoPlaying: isVideoPlaying,
                    startDelay: stampDur,
                    photoIndex: currentPhotoIndex
                )
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - AnimatedStampLayer

/// 단일 레이어(스탬프 또는 문구)에 진입 애니메이션을 부여하는 뷰.
/// .task(id: animKey) 로 모드·방향 변경 및 영상 루프/재생 시 안정적으로 재생.
private struct AnimatedStampLayer: View {
    let data:         StampData
    @Bindable var vm: StampViewModel
    let isBright:     Bool
    let entranceMode: StampEntranceMode
    let flyDirection: FlyInDirection
    /// 슬라이드 장별 config 주입 — nil이면 vm.currentConfig 사용
    var configOverride: StampPhotoConfig? = nil
    var renderOnlyStamp:  Bool   = false
    var renderOnlyText:   Bool   = false
    var previewProgress:  Double = 0
    /// 재생 버튼 누를 때 동기화용 — true로 바뀌고 progress < 0.1이면 애니메이션 재시작
    var isVideoPlaying:   Bool   = false
    /// 문구 레이어용: 스탬프 애니메이션 완료 후 등장하도록 추가 지연 (초)
    var startDelay:       Double = 0.0
    /// 슬라이드 장 인덱스 — 장이 바뀌면 animKey가 변경돼 .task가 재시작되어 애니메이션이 재생됨
    var photoIndex:       Int    = 0

    @State private var phase: Double = 0
    @State private var loopCounter: Int = 0

    private var animKey: String {
        "\(entranceMode.rawValue)-\(flyDirection.rawValue)-\(loopCounter)-\(startDelay)-\(photoIndex)"
    }

    var body: some View {
        card
            .opacity(opacityVal)
            .scaleEffect(scaleVal)
            .rotationEffect(.degrees(rotDeg))
            .offset(flyOff)
            .task(id: animKey) {
                guard entranceMode != .none else { phase = 1.0; return }
                phase = 0.0
                let delayNs = UInt64((0.12 + startDelay) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delayNs)
                guard !Task.isCancelled else { return }
                withAnimation(animCurve()) { phase = 1.0 }
            }
            // 영상 루프백 감지 (0.85 → 0.0 급락) → loopCounter 증가 → animKey 변경 → task 재시작
            .onChange(of: previewProgress) { old, new in
                if old > 0.85, new < 0.1, entranceMode != .none { loopCounter += 1 }
            }
            // 재생 버튼으로 처음부터 시작할 때 애니메이션 재시작
            // (seek 후 progress 갱신 전, isPlaying이 먼저 true가 되는 경우도 커버)
            .onChange(of: isVideoPlaying) { old, new in
                if !old, new, previewProgress < 0.1, entranceMode != .none { loopCounter += 1 }
            }
    }

    // MARK: transforms

    private var opacityVal: Double { entranceMode == .none ? 1.0 : phase }
    private var scaleVal:   Double { entranceMode == .stamp ? max(0.01, phase) : 1.0 }
    private var rotDeg:     Double { entranceMode == .stamp ? (1.0 - min(phase, 1.0)) * -4.0 : 0.0 }
    private var flyOff: CGSize {
        guard entranceMode == .flyIn else { return .zero }
        // max 클램핑 제거 → spring 오버슈트가 반대 방향 미세 바운스로 표현됨
        // (CALayer 내보내기의 startOffset * -0.06 오버슈트와 일치)
        let t = (1.0 - phase) * 220.0
        switch flyDirection {
        case .leading:  return CGSize(width: -t, height: 0)
        case .trailing: return CGSize(width:  t, height: 0)
        case .bottom:   return CGSize(width: 0,  height: t)
        }
    }

    private func animCurve() -> Animation {
        switch entranceMode {
        case .stamp: return .spring(duration: 0.42, bounce: 0.55)
        case .fade:  return .easeInOut(duration: 0.45)   // easeIn은 끝에서만 보여 안 되는 것처럼 느껴짐
        case .flyIn: return .spring(duration: 0.45, bounce: 0.20)
        case .none:  return .linear(duration: 0)
        }
    }

    private var card: some View {
        let cfg = configOverride ?? vm.currentConfig
        return StampCard(
            data: data,
            template: cfg.template,
            colorMode: cfg.colorMode,
            position: cfg.position,
            sizeLevel: cfg.sizeLevel,
            isBrightBackground: isBright,
            showHeartRate: cfg.showHeartRate,
            showCalories: cfg.showCalories,
            showTextOutline: cfg.showTextOutline,
            stampText: cfg.text,
            stampTextPosition: cfg.textPosition,
            stampTextFont: cfg.textFont,
            stampTextSize: cfg.textSize,
            stampTextColor: cfg.textColor,
            stampTextHasBorder: cfg.textHasBorder,
            renderOnlyStamp: renderOnlyStamp,
            renderOnlyText: renderOnlyText
        )
    }
}

// MARK: - ShareCardScreen extension

extension ShareCardScreen {

    // MARK: 미리보기 섹션 (9:16 letterboxed, 300×375 외부 프레임)

    @ViewBuilder
    var stampVideoPreviewSection: some View {
        let previewW: CGFloat = cardSectionH * 9.0 / 16.0
        ZStack {
            Color.black
            if previewPlayer.isBuilding {
                ProgressView().tint(.white)
                    .padding(14)
                    .background(.black.opacity(0.45))
                    .clipShape(Circle())
            } else if previewPlayer.isReady,
                      !stampVM.clipRecipes.isEmpty,
                      let pl = previewPlayer.player,
                      let cl = previewPlayer.contentLayer {
                // 현재 재생 중인 클립 인덱스 — 클립마다 길이가 다를 수 있어 누적 시간으로 계산
                let playingClipIdx: Int = {
                    guard previewPlayer.isPlaying, !stampVM.clipRecipes.isEmpty else {
                        return stampVM.selectedClipIndex
                    }
                    let totalDur = stampVM.clipRecipes.reduce(0.0) { $0 + max(0, $1.trimEnd - $1.trimStart) }
                    guard totalDur > 0 else { return 0 }
                    let currentTime = previewPlayer.progress * totalDur
                    var elapsed = 0.0
                    for (i, recipe) in stampVM.clipRecipes.enumerated() {
                        elapsed += max(0, recipe.trimEnd - recipe.trimStart)
                        if currentTime < elapsed { return i }
                    }
                    return stampVM.clipRecipes.count - 1
                }()
                let clipConfig    = stampVM.photoConfig(at: playingClipIdx)
                let clipThumb     = stampVM.clipRecipes.indices.contains(playingClipIdx)
                    ? stampVM.clipRecipes[playingClipIdx].thumbnail : nil
                let isBrightClip  = stampBackgroundIsBright(photo: clipThumb, position: clipConfig.position)
                ZStack {
                    OneLinerPreviewView(player: pl, contentLayer: cl,
                                        renderSize: previewPlayer.renderSize)
                        .brightness(CardVisual.videoBrightnessBoost)
                    // 스탬프+문구 SwiftUI 오버레이 — 등장 애니메이션 포함.
                    // CALayer 대신 SwiftUI로 렌더해 AVSynchronizedLayer 문제 우회.
                    // configOverride + currentPhotoIndex: 재생 클립 변경 시 스탬프 config·애니메이션 전환.
                    AnimatedStampPreviewCard(
                        data: stampPreviewData,
                        vm: stampVM,
                        configOverride: clipConfig,
                        isBright: isBrightClip,
                        currentPhotoIndex: playingClipIdx,
                        previewProgress: previewPlayer.progress,
                        isVideoPlaying: previewPlayer.isPlaying
                    )
                    .padding(.vertical, cardSectionH * 0.06)   // 위아래 6% 여백
                }
                .frame(width: previewW, height: cardSectionH)
                .clipped()
                .overlay(alignment: .topLeading) {
                    let videoDateStr: String = {
                        let df = DateFormatter(); df.dateFormat = "yyyy.MM.dd"
                        return df.string(from: activity.date)
                    }()
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("MIMO")
                            .font(.system(size: 7, weight: .black))
                            .tracking(2)
                            .foregroundStyle(.white)
                        Text(" RUNNING")
                            .font(.system(size: 7, weight: .bold))
                            .tracking(2)
                            .foregroundStyle(Theme.violet)
                        Spacer()
                        Text(videoDateStr)
                            .font(.system(size: 6, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .cardTextShadow()
                    .padding(.leading, previewW * 0.047)
                    .padding(.trailing, previewW * 0.05)
                    .padding(.top, cardSectionH * 0.06)
                }
                .overlay(alignment: .bottom) {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Theme.violet)
                            .frame(width: geo.size.width * previewPlayer.progress, height: 3)
                            .animation(.linear(duration: 0.1), value: previewPlayer.progress)
                    }
                    .frame(height: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 1.5))
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
                }
                Button { previewPlayer.togglePlayPause() } label: {
                    Image(systemName: previewPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white.opacity(previewPlayer.isPlaying ? 0 : 0.85))
                        .shadow(color: .black.opacity(0.5), radius: 8)
                }
                .buttonStyle(.plain)
            } else if stampVM.clipRecipes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "video.badge.plus")
                        .font(.system(size: 32))
                        .foregroundStyle(Theme.violet)
                    Text(AppLanguage.shared.s("영상을 선택해 주세요", "Select a video"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: 트림 행 — 선택된 클립의 길이 조절 슬라이더

    @ViewBuilder
    var stampTrimRow: some View {
        let idx = stampVM.selectedClipIndex
        if stampVM.clipRecipes.indices.contains(idx) {
            let r    = stampVM.clipRecipes[idx]
            let dur  = max(0.1, r.fullDuration)
            let used = max(0.1, r.trimEnd - r.trimStart)
            let fmt: (Double) -> String = { s in
                let i = Int(s); return "\(i / 60):\(String(format: "%02d", i % 60))"
            }
            VStack(spacing: 6) {
                HStack {
                    Text("\(fmt(r.trimStart)) – \(fmt(r.trimEnd))  ·  \(fmt(used)) 사용")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 24)
                TrimBarView(
                    duration:  dur,
                    trimStart: Bindable(stampVM).clipRecipes[idx].trimStart,
                    trimEnd:   Bindable(stampVM).clipRecipes[idx].trimEnd,
                    onEditingEnded: {
                        Task { await loadStampVideoPreview(data: stampPreviewData) }
                    }
                )
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 4)
        }
    }

    // MARK: 슬라이드 미리보기 섹션
    // · 배경: 선택 사진 SwiftUI Image (즉시 표시)
    // · 플레이어 준비 후: OneLinerPreviewView 오버레이 (Ken Burns + 전환 애니메이션)
    //   → onAppear seek(0.3s) 로 AVSynchronizedLayer 첫 렌더 보장
    // · 스탬프 오버레이: 항상 최상위 (9그리드 실시간 반영)

    // MARK: 슬라이드 미리보기 섹션
    //
    // ▼ 설계 원칙 (반복 버그 방지 — 수정 전 반드시 읽을 것) ▼
    //
    // [레이어 구조]
    //   1) 정적 Image (최하단): 항상 표시. 사진 선택 시 즉시 반영. cropOffsetX 적용 필수.
    //   2) OneLinerPreviewView (중간): 재생 중(isPlaying)에만 표시.
    //      · 정지 상태에서 표시하면 isReady=true인 AVPlayerLayer(흑색)가 정적 Image를 덮어
    //        사진 선택 변경이 보이지 않게 됨 → 재생 중에만 올려야 함.
    //      · 재생 시작 전 seek으로 선택 사진 위치 이동 → 올바른 사진부터 재생 시작.
    //      · AVSynchronizedLayer: 플레이어가 이미 재생 중일 때 연결되면 즉시 렌더 → seek 불필요.
    //   3) AnimatedStampPreviewCard (최상단): 스탬프·문구 SwiftUI 오버레이. 항상 표시.
    //
    // [검은 화면 방지 — PhotoSlideComposition.buildPreviewItem 주석 참고]
    //   fastBase=true 시 videoComposition 미설정 → 타임베이스만으로 AVSynchronizedLayer 구동.
    //
    // [사진 짤림 방지]
    //   정적 Image에 stampSlideCropOffsets 적용 → contentLayer 크롭과 시각적 일치.

    @ViewBuilder
    var stampSlidePreviewSection: some View {
        // 슬라이드 출력은 9:16(1080×1920). 미리보기 프레임도 동일 비율 — 4:5 카드 안에
        // 9:16 창을 두어 좌우에 여백이 생기는 것은 의도된 동작.
        // [필수] scaledToFill로 항상 채움 — "사진 밖의 공간이 보이지 않게".
        // 가로 사진: height를 맞추면 너비가 크게 넘침 → DragGesture로 좌우 이동해 크롭 위치 선택.
        let previewW: CGFloat = cardSectionH * 9.0 / 16.0
        // storyPhotos는 SwiftData JPEG 디코딩을 포함하므로 한 번만 평가해 재사용.
        let photos       = storyPhotos
        let selectedIdx  = max(0, min(stampVM.selectedClipIndex, photos.count - 1))
        let currentPhoto = photos.isEmpty ? nil : photos[selectedIdx]
        // 재생 중이면 현재 재생 장(playingIdx)의 config를 사용 → 장마다 다른 스탬프·문구 표시
        let playingIdx: Int = {
            guard previewPlayer.isPlaying, photos.count > 0 else { return selectedIdx }
            return min(Int(previewPlayer.progress * Double(photos.count)), photos.count - 1)
        }()
        let displayConfig = stampVM.photoConfig(at: playingIdx)
        let displayPhoto  = photos.indices.contains(playingIdx) ? photos[playingIdx] : currentPhoto
        let isBright      = stampBackgroundIsBright(photo: displayPhoto, position: displayConfig.position)
        // 배경으로 표시할 사진: 재생 중에는 현재 재생 장, 정지 중에는 선택된 장
        // OneLinerPreviewView(AVSynchronizedLayer) 없이 배경 사진 직접 표시 → 검은 화면 방지
        let bgIdx         = previewPlayer.isPlaying ? playingIdx : selectedIdx
        let bgPhoto       = photos.isEmpty ? nil : photos[bgIdx]
        let bgCropOffsetX = stampSlideCropOffsets[bgIdx] ?? 0.5
        // Ken Burns: PhotoSlideComposition.kenBurns와 동일한 상수·공식으로 SwiftUI 구동.
        // previewPlayer.progress가 @Observable로 매 프레임 변경 → 자동 재계산.
        let kbEndScale: CGFloat = 1.08
        let photoDur    = PhotoSlideComposition.placeableSlideDuration
        let totalDur    = photoDur * Double(max(1, photos.count))
        let photoStartT = photoDur * Double(bgIdx)
        let photoProgress = CGFloat(max(0, min(1,
            (previewPlayer.progress * totalDur - photoStartT) / photoDur)))
        let kbScale: CGFloat = bgIdx % 2 == 0
            ? 1.0 + (kbEndScale - 1.0) * photoProgress
            : kbEndScale - (kbEndScale - 1.0) * photoProgress
        let isKB = previewPlayer.isPlaying
        let dateStr: String = {
            let df = DateFormatter(); df.dateFormat = "yyyy.MM.dd"
            return df.string(from: activity.date)
        }()
        ZStack {
            // ① 배경: 재생 중이면 현재 재생 장(bgIdx) 사진, 정지 중이면 선택 장(selectedIdx) 사진.
            //    previewPlayer.progress 변경 → kbScale 재계산 → Image.scaleEffect 업데이트 → Ken Burns.
            //    SyncLayerView(AVSynchronizedLayer) 제거: fastBase 플레이어에서 animation 구동 불안정.
            //    [필수] Image에 명시적 frame을 두 겹 지정해 ZStack 크기를 previewW×cardSectionH로 고정.
            if let photo = bgPhoto {
                let scale  = max(previewW / photo.size.width, cardSectionH / photo.size.height)
                let scaledW = photo.size.width  * scale
                let scaledH = photo.size.height * scale
                let xOffset = (previewW - scaledW) * bgCropOffsetX
                let excess  = max(0.0, scaledW - previewW)
                Image(uiImage: photo)
                    .resizable()
                    .frame(width: scaledW, height: scaledH)
                    // Ken Burns: 재생 중에만 scaleEffect 적용. .clipped()가 넘치는 부분 잘라냄.
                    .scaleEffect(isKB ? kbScale : 1.0, anchor: .center)
                    .offset(x: xOffset)
                    .frame(width: previewW, height: cardSectionH, alignment: .topLeading)
                    .clipped()
                    .brightness(CardVisual.videoBrightnessBoost)
                    // 크롭 드래그: 재생 중에는 비활성화
                    .gesture(!isKB && excess > 1 ? DragGesture(minimumDistance: 1)
                        .onChanged { drag in
                            if stampSlideCropDragBase == nil {
                                stampSlideCropDragBase = stampSlideCropOffsets[selectedIdx] ?? 0.5
                            }
                            guard let base = stampSlideCropDragBase else { return }
                            stampSlideCropOffsets[selectedIdx] = max(0, min(1,
                                base - drag.translation.width / excess))
                        }
                        .onEnded { _ in stampSlideCropDragBase = nil }
                    : nil)
            } else {
                Color.black
            }
            // ③ 스탬프+문구 오버레이: 항상 최상위 (재생 중이면 playingIdx 장의 config 사용)
            //    currentPhotoIndex: playingIdx → 장이 바뀌면 animKey가 변경돼 애니메이션 재시작
            if currentPhoto != nil {
                AnimatedStampPreviewCard(
                    data: stampPreviewData,
                    vm: stampVM,
                    configOverride: displayConfig,
                    isBright: isBright,
                    currentPhotoIndex: playingIdx,
                    previewProgress: previewPlayer.isPlaying ? previewPlayer.progress : 0,
                    isVideoPlaying: previewPlayer.isPlaying
                )
                .padding(.vertical, cardSectionH * 0.06)   // 위아래 8% 여백 (출력과 동일)
            }
            // 재생 버튼 / 빌드 스피너
            if previewPlayer.isBuilding {
                ProgressView().tint(.white)
                    .padding(14)
                    .background(.black.opacity(0.45))
                    .clipShape(Circle())
            } else if previewPlayer.isReady {
                Button {
                    if previewPlayer.isPlaying {
                        previewPlayer.pause()
                    } else {
                        // 선택된 사진 시작 시각으로 seek 후 재생 → 올바른 사진부터 시작.
                        // togglePlayPause() 대신 직접 seek+play: 선택 사진과 재생 위치 동기화.
                        let t = Double(selectedIdx) * PhotoSlideComposition.placeableSlideDuration
                        previewPlayer.player?.seek(
                            to: CMTimeMakeWithSeconds(t, preferredTimescale: 600)
                        ) { _ in
                            Task { @MainActor in previewPlayer.play() }
                        }
                    }
                } label: {
                    Image(systemName: previewPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white.opacity(previewPlayer.isPlaying ? 0 : 0.85))
                        .shadow(color: .black.opacity(0.5), radius: 8)
                }
                .buttonStyle(.plain)
            } else if currentPhoto == nil {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 32))
                        .foregroundStyle(Theme.violet)
                    Text(AppLanguage.shared.s("사진을 선택해 주세요", "Select photos"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // 진행 바
            if previewPlayer.isPlaying || previewPlayer.progress > 0 {
                VStack {
                    Spacer()
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Theme.violet)
                            .frame(width: geo.size.width * previewPlayer.progress, height: 3)
                            .animation(.linear(duration: 0.1), value: previewPlayer.progress)
                    }
                    .frame(height: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 1.5))
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
                }
            }
        }
        .frame(width: previewW, height: cardSectionH)
        .clipped()
        // 워드마크(좌) + 날짜(우) — 8% 여백 바로 아래에 배치
        .overlay(alignment: .topLeading) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("MIMO")
                    .font(.system(size: 7, weight: .black))
                    .tracking(2)
                    .foregroundStyle(.white)
                Text(" RUNNING")
                    .font(.system(size: 7, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(Theme.violet)
                Spacer()
                Text(dateStr)
                    .font(.system(size: 6, weight: .medium))
                    .foregroundStyle(.white)
            }
            .cardTextShadow()
            .padding(.leading, previewW * 0.047)
            .padding(.trailing, previewW * 0.05)
            .padding(.top, cardSectionH * 0.06)
        }
    }

    // MARK: 슬라이드 미리보기 빌더
    //
    // fastBase: true → 2×2px 1fps 경량 베이스 영상 (~50ms).
    // 사진은 contentLayer(CAKeyframeAnimation)에 포함 — AVSynchronizedLayer가 타임베이스로 구동.
    // [검은 화면 방지] fastBase 시 videoComposition 미설정 필수 → PhotoSlideComposition 주석 참고.
    // [seek 보장] buildToken 변경 → UIView 재생성 → onAppear seek → AVSynchronizedLayer 렌더.

    func loadStampSlidePreview(data: StampData) async {
        guard !storyPhotos.isEmpty else { previewPlayer.invalidate(); return }
        let photos   = storyPhotos
        let dur      = PhotoSlideComposition.placeableSlideDuration
        let dummyURL = URL(fileURLWithPath: "/dev/null")
        let recipes  = photos.indices.map { i -> ClipRecipe in
            var r = ClipRecipe(url: dummyURL, fullDuration: dur)
            r.cropOffsetX = stampSlideCropOffsets[i] ?? 0.5
            return r
        }
        await previewPlayer.buildForPhotoSlides(
            photos: photos, recipes: recipes,
            activityDate: activity.date, showDate: false,
            fastBase: true)
    }

    // MARK: 미리보기 빌더 — 영상 컴포지션만 빌드, 스탬프는 SwiftUI 오버레이로 표시

    func loadStampVideoPreview(data: StampData) async {
        guard !stampVM.clipRecipes.isEmpty else {
            previewPlayer.invalidate()
            return
        }
        await previewPlayer.buildForVideoClips(
            recipes: stampVM.clipRecipes,
            activityDate: activity.date,
            showDate: false,
            muteAudio: stampVM.muteAudio)
    }
}
