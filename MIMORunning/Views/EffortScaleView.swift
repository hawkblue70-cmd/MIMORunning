import SwiftUI

/// 운동 강도 1~10 입력. 10개 가로 막대(파랑→빨강), 4구간 라벨, 출처 배지.
/// - Apple 값만 있으면 읽기 전용 → 배지 탭으로 편집 모드.
/// - 값이 없으면 바로 편집 가능.
struct EffortScaleView: View {
    let resolved: ResolvedEffort?          // 표시 값(내 입력 > Apple)
    let appleValue: Int?                   // 편집 모드에서 표식으로 남기는 Apple 값
    let onSet: (Int) -> Void               // 사용자 값 저장
    let onResetToApple: () -> Void         // 내 입력 삭제(Apple 값으로 되돌리기)

    @State private var editing = false
    @State private var dragValue: Int? = nil

    private var L: AppLanguage { AppLanguage.shared }
    private var shownValue: Int? { dragValue ?? resolved?.value }
    /// 편집 가능: 값 없음 / 내 입력 / 편집 모드 진입
    private var isEditable: Bool { resolved == nil || resolved?.source == .user || editing }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            bars
            bandLabels
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(resolved?.source == .user ? Theme.violet.opacity(0.35) : Color.white.opacity(0.07), lineWidth: 1)
        )
        .onChange(of: resolved) { _, _ in editing = false }
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 11))
                .foregroundStyle(resolved != nil ? Theme.violet : .secondary)
            Text(L.s("운동 강도", "Effort"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(resolved != nil ? .white : .secondary)
            Spacer()
            if let v = shownValue {
                Text("\(v) · \(EffortBand(value: v).label)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(EffortPalette.color(for: v))
                    .contentTransition(.numericText())
                sourceBadge
            } else {
                Text(L.s("오늘 얼마나 힘들었나요?", "How hard was it?"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var sourceBadge: some View {
        switch resolved?.source {
        case .user:
            HStack(spacing: 6) {
                badge(L.s("내 입력", "Mine"), tint: Theme.violet)
                if appleValue != nil {
                    Button(action: onResetToApple) {
                        Text(L.s("Apple 값으로", "Use Apple"))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        case .appleManual, .appleEstimated:
            Button { editing = true } label: {
                HStack(spacing: 3) {
                    badge(resolved?.source == .appleManual ? L.s("Apple 입력", "Apple") : L.s("Apple 추정", "Apple est."),
                          tint: .secondary)
                    if !editing {
                        Image(systemName: "pencil").font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        case nil:
            EmptyView()
        }
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(tint.opacity(0.12), in: Capsule())
    }

    // MARK: bars

    private var bars: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 3
            let w = (geo.size.width - spacing * 9) / 10
            HStack(spacing: spacing) {
                ForEach(1...10, id: \.self) { i in
                    ZStack {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(EffortPalette.color(for: i).opacity(filled(i) ? 1 : 0.18))
                        if editing, let a = appleValue, a == i {
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(Color.white.opacity(0.6), lineWidth: 1.5)
                        }
                    }
                    .frame(width: w, height: 28)
                    .contentShape(Rectangle())
                    .onTapGesture { if isEditable { commit(i) } }
                    .accessibilityLabel(L.s("강도 \(i)", "Effort \(i)"))
                }
            }
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { g in
                        guard isEditable else { return }
                        dragValue = value(atX: g.location.x, width: geo.size.width)
                    }
                    .onEnded { g in
                        guard isEditable else { return }
                        commit(value(atX: g.location.x, width: geo.size.width))
                    }
            )
        }
        .frame(height: 28)
        .opacity(isEditable ? 1 : 0.85)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.s("운동 강도", "Effort"))
        .accessibilityValue(shownValue.map { "\($0)" } ?? "")
        .accessibilityAdjustableAction { dir in
            guard isEditable else { return }
            let cur = shownValue ?? 5
            commit(dir == .increment ? min(10, cur + 1) : max(1, cur - 1))
        }
    }

    private func filled(_ i: Int) -> Bool { (shownValue ?? 0) >= i }

    private func value(atX x: CGFloat, width: CGFloat) -> Int {
        let ratio = min(max(x / max(width, 1), 0), 0.999)
        return Int(ratio * 10) + 1
    }

    private func commit(_ v: Int) {
        dragValue = nil
        editing = false
        onSet(v)
    }

    // MARK: band labels — 구간 폭은 막대 개수 비례(3·3·2·2)

    private var bandLabels: some View {
        GeometryReader { geo in
            let unit = geo.size.width / 10
            HStack(spacing: 0) {
                ForEach(EffortBand.allCases, id: \.self) { band in
                    Text(band.label)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: unit * CGFloat(band.range.count))
                }
            }
        }
        .frame(height: 12)
    }
}
