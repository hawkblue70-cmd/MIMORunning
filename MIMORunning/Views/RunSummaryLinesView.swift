import SwiftUI

/// 총평 줄 묶음 — 색점 + 축 + 상태어. 리듬 카드 하단과 공유 카드가 **이 컴포넌트 하나만** 쓴다(§5.8).
/// 크기는 `scale`로만 조절한다. scale=1 기준: 글자 10pt · 점 7pt · 좌우 여백 12pt · 상하 10pt · 축 열 52pt(영어 70pt).
/// 탭하면 근거·다음이 펼쳐진다(9.5pt · 라벨 8.5pt). 노란(neutral) 줄은 기본 펼침, 초록 줄은 접힘.
/// 공유 카드는 `expandAll: true`로 근거·다음까지 모두 펼쳐 그린다 — 이때는 화살표도 탭도 없다.
/// 내보내기는 `allowsExpansion: false`로 5줄만 그린다.
struct RunSummaryLinesView: View {
    let lines: [RunSummaryLine]
    var scale: CGFloat = 1.0
    var allowsExpansion: Bool = true
    /// true면 근거·다음이 있는 모든 줄을 항상 펼쳐 그린다. 화살표·탭 제스처 없음 — `allowsExpansion`은 무시된다.
    var expandAll: Bool = false

    @State private var expanded: Set<String>

    init(lines: [RunSummaryLine], scale: CGFloat = 1.0, allowsExpansion: Bool = true, expandAll: Bool = false) {
        self.lines = lines
        self.scale = scale
        self.allowsExpansion = allowsExpansion
        self.expandAll = expandAll
        _expanded = State(initialValue: allowsExpansion
            ? Set(lines.filter { $0.tone == .neutral && ($0.evidence != nil || $0.next != nil) }.map(\.axis))
            : [])
    }

    /// 축 열 폭 — 가장 긴 라벨 기준(한국어 "거리 적응" / 영어 "Training load")
    private var axisWidth: CGFloat { (AppLanguage.shared.isEnglish ? 70 : 52) * scale }

    /// 근거·다음 들여쓰기 = 점 지름 + 간격 + 축 열 폭 + 간격
    private var detailIndent: CGFloat { 7 * scale + 7 * scale + axisWidth + 7 * scale }

    var body: some View {
        VStack(alignment: .leading, spacing: 7 * scale) {
            ForEach(lines, id: \.axis) { line in
                row(line)
            }
        }
        .padding(.horizontal, 12 * scale).padding(.vertical, 10 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10 * scale))
    }

    @ViewBuilder
    private func row(_ line: RunSummaryLine) -> some View {
        let hasDetail = line.evidence != nil || line.next != nil
        let open = expandAll ? hasDetail : (allowsExpansion && hasDetail && expanded.contains(line.axis))
        let showChevron = !expandAll && allowsExpansion && hasDetail
        VStack(alignment: .leading, spacing: 3 * scale) {
            HStack(alignment: .top, spacing: 7 * scale) {
                Circle()
                    .fill(color(line.tone))
                    .frame(width: 7 * scale, height: 7 * scale)
                    .padding(.top, 3.5 * scale)
                Text(line.axis)
                    .font(.system(size: 10 * scale, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .lineLimit(1)
                    .frame(width: axisWidth, alignment: .leading)
                    .layoutPriority(1)
                Text("·")
                    .font(.system(size: 10 * scale))
                    .foregroundStyle(Color.white.opacity(0.35))
                Text(line.state)
                    .font(.system(size: 10 * scale))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineSpacing(2 * scale)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if showChevron {
                    Image(systemName: open ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9 * scale, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
            }
            if open {
                VStack(alignment: .leading, spacing: 3 * scale) {
                    if let evidence = line.evidence {
                        HStack(alignment: .top, spacing: 5 * scale) {
                            Text(AppLanguage.shared.s("근거", "Why"))
                                .font(.system(size: 8.5 * scale, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.45))
                                .frame(width: 26 * scale, alignment: .leading)
                            Text(evidence)
                                .font(.system(size: 9.5 * scale))
                                .foregroundStyle(Color.white.opacity(0.62))
                                .lineSpacing(2 * scale)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let next = line.next {
                        HStack(alignment: .top, spacing: 5 * scale) {
                            Text(AppLanguage.shared.s("다음", "Next"))
                                .font(.system(size: 8.5 * scale, weight: .semibold))
                                .foregroundStyle(color(line.tone).opacity(0.9))
                                .frame(width: 26 * scale, alignment: .leading)
                            Text(next)
                                .font(.system(size: 9.5 * scale))
                                .foregroundStyle(Color.white.opacity(0.85))
                                .lineSpacing(2 * scale)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.leading, detailIndent)
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

    private func color(_ tone: RunSummaryLine.Tone) -> Color {
        tone == .good ? Theme.positive : Theme.caution
    }
}
