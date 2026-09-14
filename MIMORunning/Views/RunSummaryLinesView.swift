import SwiftUI

/// 총평 줄 묶음 — 색점 + 축 + 상태어. 리듬 카드 하단과 공유 카드가 **이 컴포넌트 하나만** 쓴다(§5.8).
/// 크기는 `scale`로만 조절한다. scale=1 기준: 글자 10pt · 점 7pt · 좌우 여백 12pt · 상하 10pt · 축 열 52pt(영어 70pt).
/// 근거·다음은 축 이름과 같은 x에서 "- 근거 …" 형태로 시작한다(상태어 열까지 들여쓰지 않는다).
/// 노란(neutral) 줄은 어디서든 기본 펼침, 초록 줄은 접힘 — 행동이 필요한 줄만 까닭을 보여준다.
/// 글자는 사진 배경 위에서도 읽히게 밝은 흰색(축 0.92 · 상태어 1.0 · 근거 0.80 · 다음 0.96 · 라벨 0.62).
/// 공유 카드는 `expandAll: true`로 초록 줄까지 모두 펼쳐 그린다.
/// 내보내기는 `allowsExpansion: false` — 노란 줄은 펼쳐 그리되 화살표도 탭도 없다.
struct RunSummaryLinesView: View {
    let lines: [RunSummaryLine]
    var scale: CGFloat = 1.0
    var allowsExpansion: Bool = true
    /// true면 근거·다음이 있는 모든 줄을 항상 펼쳐 그린다. 화살표·탭 제스처 없음 — `allowsExpansion`은 무시된다.
    var expandAll: Bool = false
    /// 내보내기(촘촘 모드)면 줄 간격 7→5 · 상하 여백 10→7 (scale 배율은 그대로)
    @Environment(\.insightCompact) private var compact

    @State private var expanded: Set<String>

    init(lines: [RunSummaryLine], scale: CGFloat = 1.0, allowsExpansion: Bool = true, expandAll: Bool = false) {
        self.lines = lines
        self.scale = scale
        self.allowsExpansion = allowsExpansion
        self.expandAll = expandAll
        // 노란 줄은 앱·내보내기 모두 기본 펼침 — 내보내기는 탭이 없어 접혀 있으면 까닭을 볼 길이 없다
        _expanded = State(initialValue:
            Set(lines.filter { $0.tone == .neutral && ($0.evidence != nil || $0.next != nil) }.map(\.axis)))
    }

    /// 축 열 폭 — 가장 긴 라벨("거리 적응" / "Training load") + 두 글자쯤 여유
    private var axisWidth: CGFloat { (AppLanguage.shared.isEnglish ? 70 : 46) * scale }
    /// 가운뎃점 열 폭 — 고정해야 상태어 시작 x가 정해진다
    private var sepWidth: CGFloat { 5 * scale }
    /// 축 이름이 시작하는 x = 점 지름 + 간격
    private var axisStart: CGFloat { 7 * scale + 7 * scale }
    /// 상태어가 시작하는 x — 근거·다음 본문도 이 x에 맞춘다
    private var stateStart: CGFloat { axisStart + axisWidth + 7 * scale + sepWidth + 7 * scale }

    var body: some View {
        VStack(alignment: .leading, spacing: (compact ? 5 : 7) * scale) {
            ForEach(lines, id: \.axis) { line in
                row(line)
            }
        }
        .padding(.horizontal, 12 * scale).padding(.vertical, (compact ? 7 : 10) * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10 * scale))
    }

    @ViewBuilder
    private func row(_ line: RunSummaryLine) -> some View {
        let hasDetail = line.evidence != nil || line.next != nil
        let open = expandAll ? hasDetail : (hasDetail && expanded.contains(line.axis))
        let showChevron = !expandAll && allowsExpansion && hasDetail
        VStack(alignment: .leading, spacing: 3 * scale) {
            HStack(alignment: .top, spacing: 7 * scale) {
                Circle()
                    .fill(color(line.tone))
                    .frame(width: 7 * scale, height: 7 * scale)
                    .padding(.top, 3.5 * scale)
                Text(line.axis)
                    .font(.system(size: 10 * scale, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .frame(width: axisWidth, alignment: .leading)
                    .layoutPriority(1)
                Text("·")
                    .font(.system(size: 10 * scale))
                    .foregroundStyle(Color.white.opacity(0.50))
                    .frame(width: sepWidth, alignment: .center)
                Text(line.state)
                    .font(.system(size: 10 * scale))
                    .foregroundStyle(Color.white)
                    .lineSpacing(2 * scale)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if showChevron {
                    Image(systemName: open ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9 * scale, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }
            if open {
                VStack(alignment: .leading, spacing: 3 * scale) {
                    if let evidence = line.evidence {
                        detailRow(label: AppLanguage.shared.s("근거", "Why"),
                                  labelColor: Color.white.opacity(0.62),
                                  text: evidence, textColor: Color.white.opacity(0.80))
                    }
                    if let next = line.next {
                        detailRow(label: AppLanguage.shared.s("다음", "Next"),
                                  labelColor: color(line.tone).opacity(0.9),
                                  text: next, textColor: Color.white.opacity(0.96))
                    }
                }
                .padding(.leading, axisStart)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !expandAll && allowsExpansion && hasDetail else { return }
            withAnimation(.snappy) {
                if expanded.contains(line.axis) { expanded.remove(line.axis) } else { expanded.insert(line.axis) }
            }
        }
    }

    /// 근거·다음 한 줄 — 글머리 "-" + 라벨 + 본문. 본문은 상태어와 같은 x에서 시작한다.
    private func detailRow(label: String, labelColor: Color, text: String, textColor: Color) -> some View {
        let bulletWidth = 8 * scale
        return HStack(alignment: .top, spacing: 0) {
            Text("-")
                .font(.system(size: 9 * scale))
                .foregroundStyle(Color.white.opacity(0.45))
                .frame(width: bulletWidth, alignment: .leading)
            Text(label)
                .font(.system(size: 8.5 * scale, weight: .semibold))
                .foregroundStyle(labelColor)
                .frame(width: stateStart - axisStart - bulletWidth, alignment: .leading)
            Text(text)
                .font(.system(size: 9.5 * scale))
                .foregroundStyle(textColor)
                .lineSpacing(2 * scale)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func color(_ tone: RunSummaryLine.Tone) -> Color {
        tone == .good ? Theme.positive : Theme.caution
    }
}
